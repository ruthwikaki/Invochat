'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';
import type { Integration } from '@/types';

export interface DataConflict {
  id: string;
  type: 'product_duplicate' | 'inventory_mismatch' | 'price_difference' | 'sku_collision' | 'variant_inconsistency';
  severity: 'low' | 'medium' | 'high' | 'critical';
  description: string;
  sourceRecord: Record<string, any>;
  targetRecord: Record<string, any>;
  suggestedResolution: 'merge' | 'overwrite_source' | 'overwrite_target' | 'manual_review';
  confidence: number; // 0-100, confidence in the suggested resolution
  detectedAt: string;
  resolvedAt?: string;
  resolution?: 'accepted' | 'rejected' | 'modified';
  companyId: string;
  integrationId: string;
}

export interface ConflictResolutionRule {
  id: string;
  type: DataConflict['type'];
  priority: number;
  condition: string; // JSON string describing the condition
  action: 'auto_resolve' | 'flag_for_review' | 'prefer_source' | 'prefer_target' | 'merge_intelligent';
  isActive: boolean;
  companyId: string;
}

export interface ResolutionResult {
  success: boolean;
  conflictsDetected: number;
  conflictsResolved: number;
  conflictsPendingReview: number;
  errors: string[];
  resolvedConflicts: DataConflict[];
}

class DataConflictResolver {
  private static instance: DataConflictResolver;
  
  private constructor() {}
  
  static getInstance(): DataConflictResolver {
    if (!DataConflictResolver.instance) {
      DataConflictResolver.instance = new DataConflictResolver();
    }
    return DataConflictResolver.instance;
  }

  async detectAndResolveConflicts(
    integration: Integration, 
    syncData: any[], 
    syncType: 'products' | 'orders' | 'variants'
  ): Promise<ResolutionResult> {
    const result: ResolutionResult = {
      success: true,
      conflictsDetected: 0,
      conflictsResolved: 0,
      conflictsPendingReview: 0,
      errors: [],
      resolvedConflicts: [],
    };

    try {
      const conflicts = await this.detectConflicts(integration, syncData, syncType);
      result.conflictsDetected = conflicts.length;

      if (conflicts.length === 0) {
        return result;
      }

      // Get resolution rules for this company
      const rules = await this.getResolutionRules(integration.company_id);

      for (const conflict of conflicts) {
        try {
          const resolved = await this.resolveConflict(conflict, rules);
          if (resolved.resolution === 'accepted') {
            result.conflictsResolved++;
            result.resolvedConflicts.push(resolved);
          } else {
            result.conflictsPendingReview++;
          }
        } catch (error) {
          result.errors.push(`Failed to resolve conflict ${conflict.id}: ${(error as Error).message}`);
        }
      }

      // Store unresolved conflicts for manual review
      const pendingConflicts = conflicts.filter(c => 
        !result.resolvedConflicts.some(rc => rc.id === c.id)
      );
      
      if (pendingConflicts.length > 0) {
        await this.storeConflictsForReview(pendingConflicts);
      }

    } catch (error) {
      result.success = false;
      result.errors.push(`Conflict resolution failed: ${(error as Error).message}`);
      logError(error, { context: 'Data conflict resolution', integrationId: integration.id });
    }

    return result;
  }

  private async detectConflicts(
    integration: Integration, 
    syncData: any[], 
    syncType: 'products' | 'orders' | 'variants'
  ): Promise<DataConflict[]> {
    const conflicts: DataConflict[] = [];
    const supabase = getServiceRoleClient();

    switch (syncType) {
      case 'products':
        conflicts.push(...await this.detectProductConflicts(integration, syncData, supabase));
        break;
      case 'variants':
        conflicts.push(...await this.detectVariantConflicts(integration, syncData, supabase));
        break;
      case 'orders':
        conflicts.push(...await this.detectOrderConflicts(integration, syncData, supabase));
        break;
    }

    return conflicts;
  }

  private async detectProductConflicts(integration: Integration, products: any[], supabase: any): Promise<DataConflict[]> {
    const conflicts: DataConflict[] = [];

    for (const product of products) {
      // Check for duplicate products by title/handle
      const { data: existingProducts } = await supabase
        .from('products')
        .select('*')
        .eq('company_id', integration.company_id)
        .or(`title.eq.${product.title},handle.eq.${product.handle}`)
        .neq('external_product_id', product.external_product_id);

      if (existingProducts && existingProducts.length > 0) {
        for (const existing of existingProducts) {
          conflicts.push({
            id: `product_dup_${Date.now()}_${Math.random()}`,
            type: 'product_duplicate',
            severity: 'medium',
            description: `Duplicate product detected: "${product.title}" matches existing product "${existing.title}"`,
            sourceRecord: product,
            targetRecord: existing,
            suggestedResolution: 'merge',
            confidence: this.calculateSimilarity(product, existing),
            detectedAt: new Date().toISOString(),
            companyId: integration.company_id,
            integrationId: integration.id,
          });
        }
      }

      // Check for SKU collisions in variants
      if (product.variants && product.variants.length > 0) {
        for (const variant of product.variants) {
          if (variant.sku) {
            const { data: existingVariants } = await supabase
              .from('product_variants')
              .select('*, products!inner(*)')
              .eq('company_id', integration.company_id)
              .eq('sku', variant.sku)
              .neq('external_variant_id', variant.external_variant_id);

            if (existingVariants && existingVariants.length > 0) {
              conflicts.push({
                id: `sku_collision_${Date.now()}_${Math.random()}`,
                type: 'sku_collision',
                severity: 'high',
                description: `SKU collision detected: "${variant.sku}" already exists`,
                sourceRecord: variant,
                targetRecord: existingVariants[0],
                suggestedResolution: 'manual_review',
                confidence: 90,
                detectedAt: new Date().toISOString(),
                companyId: integration.company_id,
                integrationId: integration.id,
              });
            }
          }
        }
      }
    }

    return conflicts;
  }

  private async detectVariantConflicts(integration: Integration, variants: any[], supabase: any): Promise<DataConflict[]> {
    const conflicts: DataConflict[] = [];

    for (const variant of variants) {
      // Check for inventory mismatches
      const { data: existingVariant } = await supabase
        .from('product_variants')
        .select('*')
        .eq('company_id', integration.company_id)
        .eq('sku', variant.sku)
        .single();

      if (existingVariant && existingVariant.inventory_quantity !== variant.inventory_quantity) {
        const diff = Math.abs(existingVariant.inventory_quantity - variant.inventory_quantity);
        const severity = diff > 100 ? 'high' : diff > 10 ? 'medium' : 'low';

        conflicts.push({
          id: `inventory_mismatch_${Date.now()}_${Math.random()}`,
          type: 'inventory_mismatch',
          severity: severity as 'low' | 'medium' | 'high',
          description: `Inventory mismatch for SKU ${variant.sku}: existing ${existingVariant.inventory_quantity}, incoming ${variant.inventory_quantity}`,
          sourceRecord: variant,
          targetRecord: existingVariant,
          suggestedResolution: diff > 50 ? 'manual_review' : 'overwrite_source',
          confidence: diff > 50 ? 60 : 85,
          detectedAt: new Date().toISOString(),
          companyId: integration.company_id,
          integrationId: integration.id,
        });
      }

      // Check for price differences
      if (existingVariant && existingVariant.price !== variant.price) {
        const priceDiff = Math.abs(existingVariant.price - variant.price);
        const percentDiff = (priceDiff / existingVariant.price) * 100;

        if (percentDiff > 5) { // More than 5% price difference
          conflicts.push({
            id: `price_difference_${Date.now()}_${Math.random()}`,
            type: 'price_difference',
            severity: percentDiff > 20 ? 'high' : 'medium',
            description: `Significant price difference for SKU ${variant.sku}: ${percentDiff.toFixed(1)}% change`,
            sourceRecord: variant,
            targetRecord: existingVariant,
            suggestedResolution: percentDiff > 20 ? 'manual_review' : 'overwrite_source',
            confidence: percentDiff > 20 ? 70 : 90,
            detectedAt: new Date().toISOString(),
            companyId: integration.company_id,
            integrationId: integration.id,
          });
        }
      }
    }

    return conflicts;
  }

  private async detectOrderConflicts(integration: Integration, orders: any[], supabase: any): Promise<DataConflict[]> {
    const conflicts: DataConflict[] = [];

    for (const order of orders) {
      // Check for duplicate orders
      const { data: existingOrder } = await supabase
        .from('orders')
        .select('*')
        .eq('company_id', integration.company_id)
        .eq('external_order_id', order.external_order_id)
        .single();

      if (existingOrder && existingOrder.total_amount !== order.total_amount) {
        conflicts.push({
          id: `order_duplicate_${Date.now()}_${Math.random()}`,
          type: 'inventory_mismatch', // Reusing type for order amount mismatch
          severity: 'medium',
          description: `Order amount mismatch for order ${order.external_order_id}`,
          sourceRecord: order,
          targetRecord: existingOrder,
          suggestedResolution: 'manual_review',
          confidence: 80,
          detectedAt: new Date().toISOString(),
          companyId: integration.company_id,
          integrationId: integration.id,
        });
      }
    }

    return conflicts;
  }

  private calculateSimilarity(record1: any, record2: any): number {
    let similarities = 0;
    let totalChecks = 0;

    // Check title similarity
    if (record1.title && record2.title) {
      const similarity = this.stringSimilarity(record1.title, record2.title);
      similarities += similarity;
      totalChecks++;
    }

    // Check handle similarity
    if (record1.handle && record2.handle) {
      const similarity = this.stringSimilarity(record1.handle, record2.handle);
      similarities += similarity;
      totalChecks++;
    }

    // Check description similarity
    if (record1.description && record2.description) {
      const similarity = this.stringSimilarity(record1.description, record2.description);
      similarities += similarity * 0.5; // Weight description less
      totalChecks += 0.5;
    }

    return totalChecks > 0 ? Math.round((similarities / totalChecks) * 100) : 0;
  }

  private stringSimilarity(str1: string, str2: string): number {
    const longer = str1.length > str2.length ? str1 : str2;
    const shorter = str1.length > str2.length ? str2 : str1;
    
    if (longer.length === 0) return 1.0;
    
    const editDistance = this.levenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
  }

  private levenshteinDistance(str1: string, str2: string): number {
    const matrix = [];
    
    for (let i = 0; i <= str2.length; i++) {
      matrix[i] = [i];
    }
    
    for (let j = 0; j <= str1.length; j++) {
      matrix[0][j] = j;
    }
    
    for (let i = 1; i <= str2.length; i++) {
      for (let j = 1; j <= str1.length; j++) {
        if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
          matrix[i][j] = matrix[i - 1][j - 1];
        } else {
          matrix[i][j] = Math.min(
            matrix[i - 1][j - 1] + 1,
            matrix[i][j - 1] + 1,
            matrix[i - 1][j] + 1
          );
        }
      }
    }
    
    return matrix[str2.length][str1.length];
  }

  private async getResolutionRules(companyId: string): Promise<ConflictResolutionRule[]> {
    // For now, return default rules since the table doesn't exist yet
    // In a real implementation, we would create the conflict_resolution_rules table
    return this.getDefaultRules(companyId);
  }

  private getDefaultRules(companyId: string): ConflictResolutionRule[] {
    return [
      {
        id: 'default_sku_collision',
        type: 'sku_collision',
        priority: 1,
        condition: JSON.stringify({ severity: 'high' }),
        action: 'flag_for_review',
        isActive: true,
        companyId,
      },
      {
        id: 'default_inventory_small',
        type: 'inventory_mismatch',
        priority: 2,
        condition: JSON.stringify({ severity: 'low' }),
        action: 'auto_resolve',
        isActive: true,
        companyId,
      },
      {
        id: 'default_price_change',
        type: 'price_difference',
        priority: 3,
        condition: JSON.stringify({ severity: 'medium' }),
        action: 'prefer_source',
        isActive: true,
        companyId,
      },
    ];
  }

  private async resolveConflict(conflict: DataConflict, rules: ConflictResolutionRule[]): Promise<DataConflict> {
    const applicableRule = rules.find(rule => 
      rule.type === conflict.type && this.ruleMatches(rule, conflict)
    );

    if (!applicableRule) {
      // No applicable rule, flag for manual review
      return { ...conflict, suggestedResolution: 'manual_review' };
    }

    switch (applicableRule.action) {
      case 'auto_resolve':
        return await this.applyAutoResolution(conflict);
      
      case 'prefer_source':
        return await this.applySourcePreference(conflict);
      
      case 'prefer_target':
        return await this.applyTargetPreference(conflict);
      
      case 'merge_intelligent':
        return await this.applyIntelligentMerge(conflict);
      
      default:
        return { ...conflict, suggestedResolution: 'manual_review' };
    }
  }

  private ruleMatches(rule: ConflictResolutionRule, conflict: DataConflict): boolean {
    try {
      const condition = JSON.parse(rule.condition);
      
      // Simple condition matching - can be extended for more complex rules
      if (condition.severity && condition.severity !== conflict.severity) {
        return false;
      }
      
      if (condition.confidence_min && conflict.confidence < condition.confidence_min) {
        return false;
      }
      
      return true;
    } catch {
      return false;
    }
  }

  private async applyAutoResolution(conflict: DataConflict): Promise<DataConflict> {
    const supabase = getServiceRoleClient();
    
    try {
      switch (conflict.type) {
        case 'inventory_mismatch':
          // Auto-resolve by taking the source (platform) value
          await supabase
            .from('product_variants')
            .update({ inventory_quantity: conflict.sourceRecord.inventory_quantity })
            .eq('id', conflict.targetRecord.id);
          break;
        
        case 'price_difference':
          // Auto-resolve by taking the source (platform) value
          await supabase
            .from('product_variants')
            .update({ price: conflict.sourceRecord.price })
            .eq('id', conflict.targetRecord.id);
          break;
      }
      
      return {
        ...conflict,
        resolution: 'accepted',
        resolvedAt: new Date().toISOString(),
      };
    } catch (error) {
      logError(error, { context: 'Auto resolution failed', conflictId: conflict.id });
      return { ...conflict, suggestedResolution: 'manual_review' };
    }
  }

  private async applySourcePreference(conflict: DataConflict): Promise<DataConflict> {
    // Similar to auto-resolve but with logging
    logger.info(`Applying source preference for conflict ${conflict.id}`);
    return this.applyAutoResolution(conflict);
  }

  private async applyTargetPreference(conflict: DataConflict): Promise<DataConflict> {
    // Keep the existing (target) value, just mark as resolved
    return {
      ...conflict,
      resolution: 'accepted',
      resolvedAt: new Date().toISOString(),
    };
  }

  private async applyIntelligentMerge(conflict: DataConflict): Promise<DataConflict> {
    const supabase = getServiceRoleClient();
    
    try {
      switch (conflict.type) {
        case 'product_duplicate':
          // Merge product information, keeping the best of both
          const mergedProduct = {
            title: conflict.sourceRecord.title || conflict.targetRecord.title,
            description: conflict.sourceRecord.description?.length > conflict.targetRecord.description?.length 
              ? conflict.sourceRecord.description 
              : conflict.targetRecord.description,
            image_url: conflict.sourceRecord.image_url || conflict.targetRecord.image_url,
            tags: [...new Set([
              ...(conflict.sourceRecord.tags || []),
              ...(conflict.targetRecord.tags || [])
            ])],
          };
          
          await supabase
            .from('products')
            .update(mergedProduct)
            .eq('id', conflict.targetRecord.id);
          break;
      }
      
      return {
        ...conflict,
        resolution: 'accepted',
        resolvedAt: new Date().toISOString(),
      };
    } catch (error) {
      logError(error, { context: 'Intelligent merge failed', conflictId: conflict.id });
      return { ...conflict, suggestedResolution: 'manual_review' };
    }
  }

  private async storeConflictsForReview(conflicts: DataConflict[]): Promise<void> {
    const supabase = getServiceRoleClient();
    
    try {
      // Store conflicts in audit_log for now until we create a dedicated table
      const auditEntries = conflicts.map(conflict => ({
        action: 'data_conflict_detected',
        entity_type: 'product', // Default entity type for now
        entity_id: conflict.id,
        details: {
          conflictId: conflict.id,
          conflictType: conflict.type,
          severity: conflict.severity,
          description: conflict.description,
          sourceRecord: conflict.sourceRecord,
          targetRecord: conflict.targetRecord,
          suggestedResolution: conflict.suggestedResolution,
          confidence: conflict.confidence,
          detectedAt: conflict.detectedAt,
          integrationId: conflict.integrationId
        },
        company_id: conflict.companyId,
        created_at: new Date().toISOString()
      }));

      await supabase.from('audit_log').insert(auditEntries);
    } catch (error) {
      logError(error, { context: 'Failed to store conflicts for review' });
    }
  }

  async getConflictsForReview(companyId: string): Promise<DataConflict[]> {
    const supabase = getServiceRoleClient();
    
    // Query audit_log for conflict entries
    const { data: auditEntries } = await supabase
      .from('audit_log')
      .select('*')
      .eq('company_id', companyId)
      .eq('action', 'data_conflict_detected')
      .order('created_at', { ascending: false });

    return auditEntries?.map(this.mapAuditEntryToDataConflict) || [];
  }

  private mapAuditEntryToDataConflict(auditEntry: any): DataConflict {
    const details = auditEntry.details || {};
    return {
      id: details.conflictId || auditEntry.id,
      type: details.conflictType || 'product_duplicate',
      severity: details.severity || 'medium',
      description: details.description || 'Data conflict detected',
      sourceRecord: details.sourceRecord || {},
      targetRecord: details.targetRecord || {},
      suggestedResolution: details.suggestedResolution || 'manual_review',
      confidence: details.confidence || 50,
      detectedAt: details.detectedAt || auditEntry.created_at,
      companyId: auditEntry.company_id,
      integrationId: details.integrationId || '',
    };
  }

  async resolveConflictManually(
    conflictId: string, 
    resolution: 'accept_source' | 'accept_target' | 'merge' | 'ignore',
    companyId: string
  ): Promise<boolean> {
    const supabase = getServiceRoleClient();
    
    try {
      // Query audit_log for the conflict entry
      const { data: auditEntry } = await supabase
        .from('audit_log')
        .select('*')
        .eq('details->>conflictId', conflictId)
        .eq('company_id', companyId)
        .eq('action', 'data_conflict_detected')
        .single();

      if (!auditEntry) return false;

      // Apply the manual resolution
      const conflict = this.mapAuditEntryToDataConflict(auditEntry);
      await this.applyManualResolution(conflict, resolution);

      // Mark conflict as resolved by adding new audit entry
      await supabase
        .from('audit_log')
        .insert({
          action: 'data_conflict_resolved',
          entity_type: 'conflict',
          entity_id: conflictId,
          details: {
            resolution,
            resolvedAt: new Date().toISOString(),
            originalConflictId: conflictId
          },
          company_id: companyId,
          created_at: new Date().toISOString()
        });

      return true;
    } catch (error) {
      logError(error, { context: 'Manual conflict resolution failed', conflictId });
      return false;
    }
  }

  private async applyManualResolution(conflict: any, resolution: string): Promise<void> {
    const supabase = getServiceRoleClient();
    
    switch (resolution) {
      case 'accept_source':
        await this.applySourceData(conflict, supabase);
        break;
      case 'accept_target':
        // Keep existing data, no changes needed
        break;
      case 'merge':
        await this.applyMergedData(conflict, supabase);
        break;
      case 'ignore':
        // Just mark as resolved without changes
        break;
    }
  }

  private async applySourceData(conflict: any, supabase: any): Promise<void> {
    switch (conflict.type) {
      case 'inventory_mismatch':
      case 'price_difference':
        await supabase
          .from('product_variants')
          .update({
            inventory_quantity: conflict.source_record.inventory_quantity,
            price: conflict.source_record.price,
          })
          .eq('id', conflict.target_record.id);
        break;
        
      case 'product_duplicate':
        await supabase
          .from('products')
          .update(conflict.source_record)
          .eq('id', conflict.target_record.id);
        break;
    }
  }

  private async applyMergedData(conflict: any, supabase: any): Promise<void> {
    // Implement intelligent merging logic based on conflict type
    switch (conflict.type) {
      case 'product_duplicate':
        const merged = {
          title: conflict.source_record.title || conflict.target_record.title,
          description: this.mergeBestValue(
            conflict.source_record.description, 
            conflict.target_record.description
          ),
          image_url: conflict.source_record.image_url || conflict.target_record.image_url,
        };
        
        await supabase
          .from('products')
          .update(merged)
          .eq('id', conflict.target_record.id);
        break;
    }
  }

  private mergeBestValue(value1: any, value2: any): any {
    if (!value1) return value2;
    if (!value2) return value1;
    
    // For strings, return the longer one
    if (typeof value1 === 'string' && typeof value2 === 'string') {
      return value1.length > value2.length ? value1 : value2;
    }
    
    // For numbers, could implement business logic (e.g., prefer higher, lower, or more recent)
    return value1;
  }
}

export const dataConflictResolver = DataConflictResolver.getInstance();
