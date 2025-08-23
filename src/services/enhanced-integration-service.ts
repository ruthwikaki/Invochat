'use server';

import { integrationHealthMonitor } from './integration-health-monitor';
import { dataConflictResolver } from './data-conflict-resolver';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';

export interface EnhancedSyncResult {
  success: boolean;
  syncedRecords: number;
  conflicts: number;
  conflictsResolved: number;
  healthScore: number;
  errors: string[];
  warnings: string[];
  recommendations: string[];
  syncDuration: number;
  nextSyncScheduled?: string;
}

export interface BulkOperationOptions {
  batchSize?: number;
  maxConcurrency?: number;
  conflictResolution?: 'auto' | 'manual' | 'skip';
  validateData?: boolean;
  dryRun?: boolean;
}

/**
 * Enhanced integration sync with health monitoring and conflict resolution
 */
export async function performEnhancedSync(
  integrationId: string,
  companyId: string,
  syncType: 'products' | 'orders' | 'inventory' | 'all' = 'all'
): Promise<EnhancedSyncResult> {
  const startTime = Date.now();
  let syncedRecords = 0;
  let conflicts = 0;
  let conflictsResolved = 0;
  const errors: string[] = [];
  const warnings: string[] = [];
  
  try {
    logger.info('Starting enhanced sync', {
      integrationId,
      companyId,
      syncType
    });

    // Get integration details
    const supabase = getServiceRoleClient();
    const { data: integration } = await supabase
      .from('integrations')
      .select('*')
      .eq('id', integrationId)
      .eq('company_id', companyId)
      .single();

    if (!integration) {
      throw new Error('Integration not found');
    }

    // Simulate sync operation (replace with actual platform sync)
    const mockData = Array.from({ length: 50 }, (_, i) => ({
      id: `product_${i}`,
      name: `Product ${i}`,
      sku: `SKU_${i}`,
      price: Math.random() * 100
    }));

    syncedRecords = mockData.length;
    
    // Detect and resolve conflicts
    const conflictResults = await dataConflictResolver.detectAndResolveConflicts(
      integration as any,
      mockData,
      'products'
    );
    
    conflicts = conflictResults.conflictsDetected;
    conflictsResolved = conflictResults.conflictsResolved;
    
    if (conflictResults.errors.length > 0) {
      errors.push(...conflictResults.errors);
    }

    // Get health assessment
    const healthAssessment = await integrationHealthMonitor.assessIntegrationHealth(integration as any);

    const recommendations = healthAssessment.recommendations || [];
    if (healthAssessment.issues && healthAssessment.issues.length > 0) {
      warnings.push(...healthAssessment.issues.map(issue => issue.message));
    }

    return {
      success: true,
      syncedRecords,
      conflicts,
      conflictsResolved,
      healthScore: healthAssessment.healthScore,
      errors,
      warnings,
      recommendations,
      syncDuration: Date.now() - startTime,
      nextSyncScheduled: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
    };

  } catch (error) {
    logError(error, { 
      context: 'Enhanced sync failed',
      integrationId,
      companyId,
      syncType
    });

    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    errors.push(errorMessage);

    return {
      success: false,
      syncedRecords,
      conflicts,
      conflictsResolved,
      healthScore: 0,
      errors,
      warnings,
      recommendations: ['Review integration configuration', 'Check API credentials'],
      syncDuration: Date.now() - startTime
    };
  }
}

/**
 * Get comprehensive integration dashboard data
 */
export async function getIntegrationDashboard(companyId: string) {
  const supabase = getServiceRoleClient();

  try {
    // Get all integrations for the company
    const { data: integrations } = await supabase
      .from('integrations')
      .select('*')
      .eq('company_id', companyId)
      .eq('is_active', true);

    if (!integrations) {
      return {
        integrations: [],
        healthScores: {},
        activeConflicts: 0,
        recentSyncs: [],
        recommendations: [],
        alerts: []
      };
    }

    // Get health scores for each integration
    const healthScores: Record<string, number> = {};
    for (const integration of integrations) {
      const healthAssessment = await integrationHealthMonitor.assessIntegrationHealth(integration as any);
      healthScores[integration.id] = healthAssessment.healthScore;
    }

    // Get active conflicts count
    const conflictsForReview = await dataConflictResolver.getConflictsForReview(companyId);
    const activeConflicts = conflictsForReview.length;

    // Get recent sync activity from audit log
    const { data: recentSyncs } = await supabase
      .from('audit_log')
      .select('*')
      .eq('company_id', companyId)
      .in('action', ['sync_started', 'sync_completed', 'sync_failed'])
      .order('created_at', { ascending: false })
      .limit(10);

    // Generate recommendations
    const recommendations = generateDashboardRecommendations(
      integrations,
      healthScores,
      activeConflicts
    );

    return {
      integrations,
      healthScores,
      activeConflicts,
      recentSyncs: recentSyncs || [],
      recommendations,
      alerts: [] // Health alerts would be implemented with proper health monitoring tables
    };

  } catch (error) {
    logError(error, { context: 'Failed to get integration dashboard', companyId });
    
    return {
      integrations: [],
      healthScores: {},
      activeConflicts: 0,
      recentSyncs: [],
      recommendations: ['Error loading dashboard data'],
      alerts: []
    };
  }
}

// Helper functions
function generateDashboardRecommendations(
  integrations: any[],
  healthScores: Record<string, number>,
  activeConflicts: number
): string[] {
  const recommendations: string[] = [];

  // Check for low health scores
  const lowHealthIntegrations = integrations.filter(
    integration => healthScores[integration.id] < 70
  );

  if (lowHealthIntegrations.length > 0) {
    recommendations.push(
      `${lowHealthIntegrations.length} integration(s) have low health scores - review configuration`
    );
  }

  // Check for active conflicts
  if (activeConflicts > 10) {
    recommendations.push('High number of active conflicts - consider reviewing conflict resolution rules');
  }

  // Check for inactive integrations
  const inactiveCount = integrations.filter(i => !i.is_active).length;
  if (inactiveCount > 0) {
    recommendations.push(`${inactiveCount} integration(s) are inactive - consider reactivating or removing`);
  }

  return recommendations;
}
