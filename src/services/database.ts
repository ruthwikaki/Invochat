
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { DashboardMetrics, Alert, CompanySettings, UnifiedInventoryItem, User, TeamMember, Anomaly, Supplier, InventoryLedgerEntry, ExportJob, Customer, CustomerAnalytics, Sale, SaleCreateInput, InventoryAnalytics, SalesAnalytics, BusinessProfile, HealthCheckResult, Product, ProductUpdateData, InventoryAgingReportItem, ReorderSuggestion, ChannelFee } from '@/types';
import { CompanySettingsSchema, DeadStockItemSchema, SupplierSchema, AnomalySchema, SupplierFormSchema, InventoryLedgerEntrySchema, ExportJobSchema, CustomerSchema, CustomerAnalyticsSchema, SaleSchema, BusinessProfileSchema, ReorderSuggestionSchema } from '@/types';
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

export async function refreshMaterializedViews(companyId: string): Promise<void> {
    if (!isValidUuid(companyId)) return;
    await withPerformanceTracking('refreshMaterializedViews', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('refresh_materialized_views', {
            p_company_id: companyId
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

export async function getSuppliersDataFromDB(companyId: string): Promise<Supplier[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getSuppliersDataFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('suppliers').select('*').eq('company_id', companyId);

        if (error) {
            logError(error, { context: `Error fetching suppliers for company ${companyId}` });
            throw new Error(`Could not load supplier data: ${error.message}`);
        }

        return z.array(SupplierSchema).parse(data || []);
    });
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; category?: string; supplier?: string; limit?: number; offset?: number; product_id?: string }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
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
            items: parsedData.items || [],
            totalCount: parsedData.total_count,
        };
    });
}

export async function getSupplierByIdFromDB(id: string, companyId: string) {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getSupplierById', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('suppliers').select().eq('id', id).eq('company_id', companyId).single();
        if (error) {
            if (error.code === 'PGRST116') return null;
            logError(error, { context: `Failed to get supplier ${id}` });
            throw error;
        }
        return data;
    });
}

export async function createSupplierInDb(companyId: string, formData: SupplierFormData) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    const parsedData = SupplierFormSchema.parse(formData);
    return withPerformanceTracking('createSupplierInDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('suppliers').insert({ ...parsedData, company_id: companyId });
        if (error) {
            logError(error, { context: 'Failed to create supplier' });
            throw error;
        }
    });
}

export async function updateSupplierInDb(id: string, companyId: string, formData: SupplierFormData) {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    const parsedData = SupplierFormSchema.parse(formData);
    return withPerformanceTracking('updateSupplierInDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('suppliers').update(parsedData).eq('id', id).eq('company_id', companyId);
        if (error) {
            logError(error, { context: `Failed to update supplier ${id}` });
            throw error;
        }
    });
}

export async function deleteSupplierFromDb(id: string, companyId: string) {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteSupplierFromDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('suppliers').delete().eq('id', id).eq('company_id', companyId);
        if (error) {
            logError(error, { context: `Failed to delete supplier ${id}` });
            throw error;
        }
    });
}

export async function softDeleteInventoryItemsFromDb(companyId: string, productIds: string[], userId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('softDeleteInventoryItemsFromDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase
            .from('inventory')
            .update({ deleted_at: new Date().toISOString(), deleted_by: userId })
            .in('id', productIds)
            .eq('company_id', companyId);
        if (error) {
            logError(error, { context: `Failed to soft-delete inventory items` });
            throw error;
        }
    });
}

export async function updateProductInDb(companyId: string, productId: string, data: ProductUpdateData) {
    if (!isValidUuid(companyId) || !isValidUuid(productId)) throw new Error('Invalid ID format.');
    const parsedData = ProductUpdateSchema.parse(data);
    return withPerformanceTracking('updateProductInDb', async () => {
        const supabase = getServiceRoleClient();
        const { data: updated, error } = await supabase
            .from('inventory')
            .update({ ...parsedData, updated_at: new Date().toISOString() })
            .eq('id', productId)
            .eq('company_id', companyId)
            .select()
            .single();

        if (error) {
            logError(error, { context: `Failed to update product ${productId}` });
            throw error;
        }
        return updated;
    });
}


export async function getInventoryLedgerForSkuFromDB(companyId: string, productId: string): Promise<InventoryLedgerEntry[]> {
    if (!isValidUuid(companyId) || !isValidUuid(productId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getInventoryLedgerForSkuFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('inventory_ledger')
            .select('*')
            .eq('company_id', companyId)
            .eq('product_id', productId)
            .order('created_at', { ascending: false })
            .limit(100);

        if (error) {
            logError(error, { context: `Failed to get inventory ledger for product ${productId}` });
            throw error;
        }
        return z.array(InventoryLedgerEntrySchema).parse(data || []);
    });
}

export async function getCustomersFromDB(companyId: string, params: { query?: string, limit: number, offset: number }) {
     if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getCustomersFromDB', async () => {
        const supabase = getServiceRoleClient();
        let query = supabase.from('customer_analytics_metrics').select('*', { count: 'exact' }).eq('company_id', companyId);
        
        if (params.query) {
            query = query.or(`customer_name.ilike.%${params.query}%,email.ilike.%${params.query}%`);
        }

        const { data, count, error } = await query
            .order('total_spent', { ascending: false })
            .range(params.offset, params.offset + params.limit - 1);
        
        if (error) {
            logError(error, { context: `Failed to fetch customers for company ${companyId}` });
            throw error;
        }

        const CustomerStatSchema = z.object({
            id: z.string().uuid(),
            customer_name: z.string(),
            email: z.string().email().nullable(),
            total_orders: z.number().int(),
            total_spent: z.number(), // in cents
        });
        
        return { items: z.array(CustomerSchema).parse(data || []), totalCount: count || 0 };
    });
}

export async function deleteCustomerFromDb(customerId: string, companyId: string) {
    if (!isValidUuid(customerId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteCustomerFromDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase
            .from('customers')
            .update({ deleted_at: new Date().toISOString() })
            .eq('id', customerId)
            .eq('company_id', companyId);
            
        if (error) {
            logError(error, { context: `Failed to delete customer ${customerId}` });
            throw error;
        }
    });
}

export async function searchProductsForSaleInDB(companyId: string, query: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    if (!query || query.length < 2) return [];

    return withPerformanceTracking('searchProductsForSaleInDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('inventory')
            .select('id, sku, name, price, quantity')
            .eq('company_id', companyId)
            .or(`name.ilike.%${query}%,sku.ilike.%${query}%`)
            .is('deleted_at', null)
            .limit(10);
            
        if (error) {
            logError(error, { context: `Product search failed for company ${companyId}` });
            return [];
        }
        
        const SearchResultSchema = z.object({
            product_id: z.string().uuid().readonly(),
            sku: z.string(),
            product_name: z.string(),
            price: z.number().nullable(),
            quantity: z.number(),
        });
        
        // This is a transformation, not a validation. Map id to product_id
        const transformedData = data.map(d => ({
            product_id: d.id,
            sku: d.sku,
            product_name: d.name,
            price: d.price,
            quantity: d.quantity
        }));

        return transformedData;
    });
}

export async function recordSaleInDB(companyId: string, userId: string, saleData: SaleCreateInput) {
    if (!isValidUuid(companyId) || !isValidUuid(userId)) throw new Error('Invalid ID format.');
    const parsedData = SaleCreateSchema.parse(saleData);
    
    return withPerformanceTracking('recordSaleInDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('record_sale_transaction', {
            p_company_id: companyId,
            p_user_id: userId,
            p_sale_items: parsedData.items,
            p_customer_name: parsedData.customer_name,
            p_customer_email: parsedData.customer_email,
            p_payment_method: parsedData.payment_method,
            p_notes: parsedData.notes,
            p_external_id: null
        }).single();
        
        if (error) {
            logError(error, { context: 'record_sale_transaction RPC failed' });
            throw error;
        }

        await invalidateCompanyCache(companyId, ['dashboard']);
        return data;
    });
}

export async function getSalesFromDB(companyId: string, params: { query?: string, page: number, limit: number, offset: number }) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getSalesFromDB', async () => {
        const supabase = getServiceRoleClient();
        let query = supabase.from('sales').select('*', { count: 'exact' }).eq('company_id', companyId);
        if (params.query) {
            query = query.or(`sale_number.ilike.%${params.query}%,customer_name.ilike.%${params.query}%,customer_email.ilike.%${params.query}%`);
        }
        
        const { data, count, error } = await query
            .order('created_at', { ascending: false })
            .range(params.offset, params.offset + params.limit - 1);

        if (error) {
            logError(error, { context: `Failed to fetch sales for company ${companyId}` });
            throw error;
        }
        return { items: z.array(SaleSchema).parse(data || []), totalCount: count || 0 };
    });
}


export async function getSalesAnalyticsFromDB(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getSalesAnalyticsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_sales_analytics', { p_company_id: companyId }).single();
        if (error) {
            logError(error, { context: 'get_sales_analytics RPC failed' });
            throw error;
        }
        return SalesAnalyticsSchema.parse(data);
    });
}

export async function getCustomerAnalyticsFromDB(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getCustomerAnalyticsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_customer_analytics', { p_company_id: companyId }).single();
        if (error) {
            logError(error, { context: 'get_customer_analytics RPC failed' });
            throw error;
        }
        return CustomerAnalyticsSchema.parse(data);
    });
}


// --- System & Test Actions ---

export async function testSupabaseConnection(): Promise<{ isConfigured: boolean; success: boolean; user: any; error?: Error; }> {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
        return { isConfigured: false, success: false, user: null, error: new Error('One or more Supabase environment variables are missing.') };
    }

    try {
        const supabase = getServiceRoleClient();
        const { data: { user }, error } = await supabase.auth.getUser();
        if (error) throw error;
        return { isConfigured: true, success: true, user };
    } catch (e: any) {
        return { isConfigured: true, success: false, user: null, error: e };
    }
}

export async function testDatabaseQuery(): Promise<{ success: boolean; error?: string; }> {
    try {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('inventory').select('id').limit(1);
        if (error) throw error;
        return { success: true };
    } catch (e: any) {
        return { success: false, error: e.message };
    }
}

export async function logUserFeedbackInDb(userId: string, companyId: string, subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful') {
    if (!isValidUuid(userId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('logUserFeedbackInDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('audit_log').insert({
            user_id: userId,
            company_id: companyId,
            action: 'feedback_submitted',
            details: {
                subject_id: subjectId,
                subject_type: subjectType,
                feedback: feedback
            }
        });
        if (error) {
            logError(error, { context: `Failed to log user feedback for user ${userId}` });
            throw error;
        }
    });
}


export async function getDeadStockReportFromDB(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getDeadStockReportFromDB', async () => {
        const supabase = getServiceRoleClient();
        const settings = await getSettings(companyId);
        
        const { data, error } = await supabase.rpc('get_dead_stock_report', { p_company_id: companyId, p_dead_stock_days: settings.dead_stock_days });
        if (error) {
            logError(error, { context: 'get_dead_stock_report RPC failed' });
            throw error;
        }

        const ReportSchema = z.object({
            items: z.array(DeadStockItemSchema),
            total_value: z.number(),
            total_units: z.number().int(),
        });
        
        const result = ReportSchema.parse(data);

        return {
            deadStockItems: result.items,
            totalValue: result.total_value,
            totalUnits: result.total_units,
        };
    });
}

export async function getReorderReportFromDB(companyId: string): Promise<ReorderSuggestion[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getReorderReportFromDB', async () => {
        const supabase = getServiceRoleClient();
        const settings = await getSettings(companyId);
        
        const { data, error } = await supabase.rpc('get_reorder_suggestions', {
            p_company_id: companyId,
            p_timezone: settings.timezone
        });
        
        if (error) {
            logError(error, { context: 'get_reorder_suggestions RPC failed' });
            throw error;
        }

        return z.array(ReorderSuggestionSchema).parse(data || []);
    });
}

export async function getInventoryHealthScoreFromDB(companyId: string) {
    // Placeholder function
    return { score: 85, summary: 'Overall inventory health is good.' };
}

export async function findProfitLeaksFromDB(companyId: string) {
    // Placeholder function
    return [];
}

export async function getAbcAnalysisFromDB(companyId: string, metric: 'revenue' | 'units' | 'profit', period: 'last30' | 'last90' | 'last365') {
    // Placeholder function
    return [];
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getAlertsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_alerts', { p_company_id: companyId });
        if (error) {
            logError(error, { context: `get_alerts RPC failed for company ${companyId}` });
            throw error;
        }
        
        const AlertRpcItemSchema = z.object({
            type: z.enum(['low_stock', 'dead_stock', 'predictive']),
            sku: z.string(),
            product_name: z.string(),
            current_stock: z.number().int(),
            reorder_point: z.number().int().nullable(),
            last_sold_date: z.string().datetime().nullable(),
            value: z.number(),
            days_of_stock_remaining: z.number().nullable(),
        });
        
        const parsedData = z.array(AlertRpcItemSchema).parse(data || []);

        return parsedData.map(item => ({
            id: `${item.type}-${item.sku}`,
            type: item.type,
            title: item.type.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase()),
            message: `Item ${item.product_name} (${item.sku}) has triggered a ${item.type} alert.`,
            severity: item.type === 'low_stock' ? 'warning' : 'info',
            timestamp: new Date().toISOString(),
            metadata: {
                productId: item.sku, // Assuming sku can be used as an identifier for linking
                productName: item.product_name,
                currentStock: item.current_stock,
                reorderPoint: item.reorder_point,
                lastSoldDate: item.last_sold_date,
                value: item.value,
                daysOfStockRemaining: item.days_of_stock_remaining
            }
        }));
    });
}

export async function getAnomalyInsightsFromDB(companyId: string): Promise<Anomaly[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getAnomalyInsightsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_anomaly_insights', { p_company_id: companyId });
        if (error) {
            logError(error, { context: `get_anomaly_insights RPC failed for company ${companyId}` });
            throw error;
        }
        return z.array(AnomalySchema).parse(data || []);
    });
}

export async function getDbSchemaAndData(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getDbSchemaAndData', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_schema_and_data', { p_company_id: companyId });
        if (error) {
            logError(error, { context: `get_schema_and_data RPC failed for company ${companyId}` });
            throw error;
        }
        return data || [];
    });
}

export async function getInventoryAnalyticsFromDB(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getInventoryAnalyticsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_inventory_analytics', { p_company_id: companyId }).single();
        if (error) {
            logError(error, { context: 'get_inventory_analytics RPC failed' });
            throw error;
        }
        return InventoryAnalyticsSchema.parse(data);
    });
}

export async function getBusinessProfile(companyId: string): Promise<BusinessProfile> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getBusinessProfile', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_business_profile', { p_company_id: companyId }).single();
        if (error) {
            logError(error, { context: 'get_business_profile RPC failed' });
            throw error;
        }
        return BusinessProfileSchema.parse(data);
    });
}


export async function healthCheckInventoryConsistency(companyId: string): Promise<HealthCheckResult> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('health_check_inventory_consistency', { p_company_id: companyId }).single();
    if (error) {
        logError(error, { context: `health_check_inventory_consistency RPC failed` });
        return { healthy: false, metric: -1, message: "Could not run the health check: " + error.message };
    }
    return data;
}

export async function healthCheckFinancialConsistency(companyId: string): Promise<HealthCheckResult> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('health_check_financial_consistency', { p_company_id: companyId }).single();
    if (error) {
        logError(error, { context: `health_check_financial_consistency RPC failed` });
        return { healthy: false, metric: -1, message: "Could not run the health check: " + error.message };
    }
    return data;
}

export async function createExportJobInDb(companyId: string, userId: string): Promise<ExportJob> {
    if (!isValidUuid(companyId) || !isValidUuid(userId)) throw new Error('Invalid ID format.');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('export_jobs')
        .insert({ company_id: companyId, requested_by_user_id: userId })
        .select()
        .single();
    if (error) {
        logError(error, { context: 'Failed to create export job.' });
        throw error;
    }
    return ExportJobSchema.parse(data);
}

export async function getInventoryAgingReportFromDB(companyId: string): Promise<InventoryAgingReportItem[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getInventoryAgingReportFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_inventory_aging_report', { p_company_id: companyId });
        if (error) {
            logError(error, { context: 'get_inventory_aging_report RPC failed' });
            throw error;
        }
        return z.array(InventoryAgingReportItemSchema).parse(data || []);
    });
}


export async function getChannelFeesFromDB(companyId: string): Promise<ChannelFee[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getChannelFeesFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('channel_fees')
            .select('*')
            .eq('company_id', companyId);
        if (error) {
            logError(error, { context: 'Failed to fetch channel fees' });
            throw error;
        }
        return data as ChannelFee[];
    });
}

export async function upsertChannelFeeInDB(companyId: string, feeData: Omit<ChannelFee, 'id' | 'company_id'>) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('upsertChannelFeeInDB', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('channel_fees').upsert(
            { ...feeData, company_id: companyId },
            { onConflict: 'company_id, channel_name' }
        );
        if (error) {
            logError(error, { context: 'Failed to upsert channel fee' });
            throw error;
        }
    });
}
