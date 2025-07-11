
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { DashboardMetrics, Alert, CompanySettings, UnifiedInventoryItem, User, TeamMember, Anomaly, Supplier, InventoryUpdateData, InventoryLedgerEntry, ExportJob, Customer, CustomerAnalytics, Sale, SaleCreateInput, InventoryAnalytics, SalesAnalytics, BusinessProfile, HealthCheckResult, Product, ProductUpdateData, InventoryAgingReportItem } from '@/types';
import { CompanySettingsSchema, DeadStockItemSchema, SupplierSchema, AnomalySchema, LocationSchema, LocationFormSchema, SupplierFormSchema, InventoryUpdateSchema, InventoryLedgerEntrySchema, ExportJobSchema, CustomerSchema, CustomerAnalyticsSchema, SaleSchema, BusinessProfileSchema } from '@/types';
import { redisClient, isRedisEnabled, invalidateCompanyCache } from '@/lib/redis';
import { trackDbQueryPerformance, incrementCacheHit, incrementCacheMiss } from './monitoring';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { redirect } from 'next/navigation';
import type { Integration } from '@/features/integrations/types';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { generateAnomalyExplanation } from '@/ai/flows/anomaly-explanation-flow';


export const isValidUuid = (uuid: string) => /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);

export async function withPerformanceTracking<T>(
    functionName: string,
    fn: () => Promise<T>
): Promise<T> {
    const startTime = performance.now();
    try {
        return await fn();
    } finally {
        const endTime = performance.now();
        trackDbQueryPerformance(functionName, endTime - startTime);
    }
}

export async function refreshMaterializedViews(companyId: string, viewNames?: ('company_dashboard_metrics' | 'customer_analytics_metrics')[]): Promise<void> {
    if (!isValidUuid(companyId)) return;
    const viewsToRefresh = viewNames || ['company_dashboard_metrics', 'customer_analytics_metrics'];
    await withPerformanceTracking('refreshMaterializedViews', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('refresh_materialized_views', {
            p_company_id: companyId,
            p_view_names: viewsToRefresh
        });
        if (error) {
            logError(error, { context: `Failed to refresh materialized views for company ${companyId}` });
        } else {
            logger.info(`[DB Service] Refreshed materialized views for company ${companyId}`);
        }
    });
}

export async function getSettings(companyId: string): Promise<CompanySettings> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    
    return withPerformanceTracking('getCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('company_settings')
            .select('*')
            .eq('company_id', companyId)
            .single();
        
        if (error && error.code !== 'PGRST116') {
            logError(error, { context: `Error fetching company settings for ${companyId}` });
            throw error;
        }

        if (data) {
            return CompanySettingsSchema.parse(data);
        }

        logger.info(`[DB Service] No settings found for company ${companyId}. Creating defaults.`);
        const defaultSettingsData = {
            company_id: companyId,
            dead_stock_days: config.businessLogic.deadStockDays,
            overstock_multiplier: config.businessLogic.overstockMultiplier,
            high_value_threshold: config.businessLogic.highValueThreshold,
            fast_moving_days: config.businessLogic.fastMovingDays,
            predictive_stock_days: config.businessLogic.predictiveStockDays,
            currency: 'USD',
            timezone: 'UTC',
            tax_rate: 0,
            custom_rules: {},
        };
        
        const { data: newData, error: insertError } = await supabase
            .from('company_settings')
            .upsert(defaultSettingsData)
            .select()
            .single();
        
        if (insertError) {
            logError(insertError, { context: `Failed to insert default settings for company ${companyId}` });
            throw insertError;
        }

        return CompanySettingsSchema.parse(newData);
    });
}

const CompanySettingsUpdateSchema = z.object({
    dead_stock_days: z.coerce.number().int().positive('Dead stock days must be a positive number.').optional(),
    fast_moving_days: z.coerce.number().int().positive('Fast-moving days must be a positive number.').optional(),
    overstock_multiplier: z.coerce.number().positive('Overstock multiplier must be a positive number.').optional(),
    high_value_threshold: z.coerce.number().int().positive('High-value threshold must be a positive number.').optional(),
    predictive_stock_days: z.coerce.number().int().positive('Predictive stock days must be a positive number.').optional(),
});


export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<CompanySettings> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');

    const parsedSettings = CompanySettingsUpdateSchema.partial().safeParse(settings);
    
    if (!parsedSettings.success) {
        const errorMessages = parsedSettings.error.issues.map(issue => issue.message).join(' ');
        throw new Error(`Invalid settings format: ${errorMessages}`);
    }

    return withPerformanceTracking('updateCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase
            .from('company_settings')
            .update({ ...parsedSettings.data, updated_at: new Date().toISOString() })
            .eq('company_id', companyId)
            .select()
            .single();
            
        if (error) {
            logError(error, { context: `Error updating settings for ${companyId}` });
            throw error;
        }
        
        logger.info(`[Cache Invalidation] Business settings updated. Invalidating relevant caches for company ${companyId}.`);
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        
        return CompanySettingsSchema.parse(data);
    });
}

export async function getDashboardMetrics(companyId: string, dateRange: string = '30d'): Promise<DashboardMetrics> {
  if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
  const cacheKey = `company:${companyId}:dashboard:${dateRange}`;

  if (isRedisEnabled) {
    try {
      const cachedData = await redisClient.get(cacheKey);
      if (cachedData) {
        logger.info(`[Cache] HIT for dashboard metrics: ${cacheKey}`);
        await incrementCacheHit('dashboard');
        return JSON.parse(cachedData);
      }
      logger.info(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
      await incrementCacheMiss('dashboard');
    } catch (error) {
        logError(error, { context: `Redis error getting cache for ${cacheKey}` });
    }
  }

  const fetchAndCacheMetrics = async (): Promise<DashboardMetrics> => {
    return withPerformanceTracking('getDashboardMetricsOptimized', async () => {
        const supabase = getServiceRoleClient();
        const days = parseInt(dateRange.replace('d', ''), 10) || 30;
        
        const { data: mvData, error: mvError } = await supabase
            .from('company_dashboard_metrics')
            .select('inventory_value, low_stock_count, total_skus')
            .eq('company_id', companyId)
            .maybeSingle();

        if (mvError) {
            logError(mvError, { context: `Could not fetch from dashboard metrics table for company ${companyId}` });
        }
        
        const { data: rpcData, error: rpcError } = await supabase.rpc('get_dashboard_metrics', {
            p_company_id: companyId,
            p_days: days,
        });
        
        if (rpcError) {
            logError(rpcError, { context: `Dashboard RPC failed for company ${companyId}` });
            throw rpcError;
        }

        const metrics = rpcData || {};
        
        const { count: customerCount, error: customerError } = await supabase.from('customers').select('id', { count: 'exact', head: true }).eq('company_id', companyId);

        if (customerError) {
            logError(customerError, { context: `Could not fetch customer count for company ${companyId}`});
        }

        const finalMetrics: DashboardMetrics = {
            totalSalesValue: Math.round(metrics.totalSalesValue || 0),
            totalProfit: Math.round(metrics.totalProfit || 0),
            totalInventoryValue: Math.round(mvData?.inventory_value || 0),
            lowStockItemsCount: mvData?.low_stock_count || 0,
            deadStockItemsCount: metrics.deadStockItemsCount || 0,
            totalSkus: mvData?.total_skus || 0,
            totalOrders: metrics.totalOrders || 0,
            totalCustomers: customerCount || 0,
            averageOrderValue: metrics.averageOrderValue || 0,
            salesTrendData: (metrics.salesTrendData as { date: string; Sales: number }[] | null) ?? [],
            inventoryByCategoryData: (metrics.inventoryByCategoryData as { name: string; value: number }[] | null) ?? [],
            topCustomersData: (metrics.topCustomersData as { name: string; value: number }[] | null) ?? [],
        };
        
        if (isRedisEnabled) {
            try {
                await redisClient.set(cacheKey, JSON.stringify(finalMetrics), 'EX', config.redis.ttl.dashboard);
                logger.info(`[Cache] SET for dashboard metrics: ${cacheKey}`);
            } catch (error) {
                logError(error, { context: `Redis error setting cache for ${cacheKey}` });
            }
        }
        return finalMetrics;
    });
  };

  return fetchAndCacheMetrics();
}

export async function getInventoryCategoriesFromDB(companyId: string): Promise<string[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getInventoryCategoriesFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase.rpc('get_distinct_categories', {
            p_company_id: companyId
        });

        if (error) {
            logError(error, { context: `Error fetching inventory categories for company ${companyId}` });
            return [];
        }
        
        return data.map((item: { category: string }) => item.category) ?? [];
    });
}

export async function getTeamMembersFromDB(companyId: string): Promise<TeamMember[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getTeamMembersFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('users')
            .select('id, email, role')
            .eq('company_id', companyId)
            .is('deleted_at', null);

        if (error) {
            logError(error, { context: `Error fetching team members for company ${companyId}` });
            throw error;
        }
        return (data ?? []) as TeamMember[];
    });
}

export async function inviteUserToCompanyInDb(companyId: string, companyName: string, email: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('inviteUserToCompany', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.auth.admin.inviteUserByEmail(email, {
            data: {
                company_id: companyId,
                company_name: companyName,
                role: 'Member'
            },
            redirectTo: `${config.app.url}/dashboard`,
        });

        if (error) {
            logError(error, { context: `Error inviting user ${email} to company ${companyId}` });
            if (error.message.includes('User already exists')) {
                throw new Error('This user already exists in the system. They cannot be invited again.');
            }
            if (error.message.includes('already been invited')) {
                throw new Error('This user has already been invited. They need to accept the existing invitation from their email.');
            }
            throw error;
        }

        return data;
    });
}

export async function removeTeamMemberFromDb(
    userIdToRemove: string,
    companyId: string,
    performingUserId: string,
): Promise<{ success: boolean; error?: string }> {
    if (!isValidUuid(userIdToRemove) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('removeTeamMemberFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        const { error } = await supabase
            .from('users')
            .update({ deleted_at: new Date().toISOString() })
            .eq('id', userIdToRemove)
            .eq('company_id', companyId);

        if (error) {
            logError(error, { context: `Failed to soft-delete user ${userIdToRemove} from company ${companyId}` });
            return { success: false, error: error.message };
        }

        return { success: true };
    });
}

export async function updateTeamMemberRoleInDb(
    memberIdToUpdate: string,
    companyId: string,
    newRole: 'Admin' | 'Member'
): Promise<{ success: boolean; error?: string }> {
     if (!isValidUuid(memberIdToUpdate) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
     return withPerformanceTracking('updateTeamMemberRoleInDb', async () => {
        const supabase = getServiceRoleClient();
        
        const { data: memberData } = await supabase.from('users').select('role').eq('id', memberIdToUpdate).single();
        if (memberData?.role === 'Owner') {
            return { success: false, error: "The Company Owner's role cannot be changed." };
        }

        const { error: updateError } = await supabase
            .from('users')
            .update({ role: newRole })
            .eq('id', memberIdToUpdate)
            .eq('company_id', companyId);

        if (updateError) {
            logError(updateError, { context: `Failed to update role for ${memberIdToUpdate}` });
            return { success: false, error: updateError.message };
        }
        
        const { error: authUpdateError } = await supabase.auth.admin.updateUserById(memberIdToUpdate, {
            app_metadata: { role: newRole }
        });
        
        if (authUpdateError) {
            logError(authUpdateError, { context: `Failed to auth role for ${memberIdToUpdate}` });
        }

        return { success: true };
    });
}

export async function getSuppliersWithPerformanceFromDB(companyId: string): Promise<Supplier[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getSuppliersWithPerformanceFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('suppliers').select('*').eq('company_id', companyId);

        if (error) {
            logError(error, { context: `Error fetching suppliers for company ${companyId}` });
            throw new Error(`Could not load supplier data: ${error.message}`);
        }

        return z.array(SupplierSchema).parse(data || []);
    });
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; category?: string; location?: string; supplier?: string; limit?: number; offset?: number; product_id?: string }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getUnifiedInventoryFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_unified_inventory', {
            p_company_id: companyId,
            p_query: params.query || null,
            p_category: params.category || null,
            p_supplier_id: params.supplier ? (isValidUuid(params.supplier) ? params.supplier : null) : null,
            p_product_id_filter: params.product_id || null,
            p_limit: params.limit || 50,
            p_offset: params.offset || 0,
        });

        if (error) {
            logError(error, { context: 'getUnifiedInventoryFromDB RPC failed' });
            throw new Error(`Could not load inventory data: ${error.message}`);
        }
        
        const RpcResponseSchema = z.object({
            items: z.array(UnifiedInventoryItemSchema).nullable().default([]),
            total_count: z.coerce.number().default(0),
        });
        
        const responseData = data && data.length > 0 ? data[0] : { items: [], total_count: 0 };
        const parsedData = RpcResponseSchema.parse(responseData);
        
        return {
            items: parsedData.items,
            totalCount: parsedData.total_count,
        };
    });
}
