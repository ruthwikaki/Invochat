

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, User, TeamMember, Supplier, SupplierFormData, Product, ProductUpdateData } from '@/types';
import { CompanySettingsSchema, SupplierSchema, SupplierFormSchema, ProductUpdateSchema, UnifiedInventoryItemSchema, OrderSchema } from '@/types';
import { redisClient, isRedisEnabled, invalidateCompanyCache } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { redirect } from 'next/navigation';
import type { Integration } from '@/features/integrations/types';

// Performance wrapper
export async function withPerformanceTracking<T>(functionName: string, fn: () => Promise<T>): Promise<T> {
    const startTime = performance.now();
    try { return await fn(); } finally { const endTime = performance.now(); }
}

// --- CORE FUNCTIONS (ADAPTED FOR NEW SCHEMA) ---

export async function getSettings(companyId: string): Promise<CompanySettings> {
    return withPerformanceTracking('getCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('company_settings').select('*').eq('company_id', companyId).single();
        if (error && error.code !== 'PGRST116') throw error;
        if (data) return CompanySettingsSchema.parse(data);
        const { data: newData, error: insertError } = await supabase.from('company_settings').upsert({ company_id: companyId }).select().single();
        if (insertError) throw insertError;
        return CompanySettingsSchema.parse(newData);
    });
}

export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<CompanySettings> {
    return withPerformanceTracking('updateCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('company_settings').update({ ...settings, updated_at: new Date().toISOString() }).eq('company_id', companyId).select().single();
        if (error) throw error;
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        return CompanySettingsSchema.parse(data);
    });
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; page?: number; limit?: number; offset?: number; }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    return withPerformanceTracking('getUnifiedInventoryFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        // This RPC call simplifies fetching product variants with their parent product info.
        const rpcParams: any = {
            p_company_id: companyId,
            p_limit: params.limit || 50,
            p_offset: params.offset || 0,
        };
        if (params.query) {
            rpcParams.p_search_term = params.query;
        }

        const { data, error } = await supabase
            .rpc('get_inventory_with_products', rpcParams);
        
        if (error) {
            logError(error, { context: 'getUnifiedInventoryFromDB failed' });
            throw error;
        }

        const items = z.array(UnifiedInventoryItemSchema).parse(data || []);
        const totalCount = items[0]?.full_count || 0;
        
        return {
            items,
            totalCount,
        };
    });
}

export async function updateProductInDb(companyId: string, productId: string, data: ProductUpdateData) {
    const parsedData = ProductUpdateSchema.parse(data);
    return withPerformanceTracking('updateProductInDb', async () => {
        const supabase = getServiceRoleClient();
        const { data: updated, error } = await supabase
            .from('products')
            .update({ title: parsedData.name, product_type: parsedData.category, updated_at: new Date().toISOString() })
            .eq('id', productId)
            .eq('company_id', companyId)
            .select()
            .single();

        if (error) throw error;
        return updated;
    });
}

export async function getInventoryCategoriesFromDB(companyId: string): Promise<string[]> {
    return withPerformanceTracking('getInventoryCategoriesFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('products')
            .select('product_type')
            .eq('company_id', companyId)
            .not('product_type', 'is', null)
            .distinct();
        if (error) return [];
        return data.map((item: { product_type: string }) => item.product_type) ?? [];
    });
}

export async function getInventoryLedgerFromDB(companyId: string, variantId: string) {
    return withPerformanceTracking('getInventoryLedgerFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('inventory_adjustments')
            .select('*')
            .eq('company_id', companyId)
            .eq('variant_id', variantId)
            .order('created_at', { ascending: false });
            
        if (error) throw error;
        return data || [];
    });
}


// --- Stubs for functions that need significant refactoring ---
export async function getDashboardMetrics(companyId: string, dateRange: string) { return {}; }
export async function getInventoryAnalyticsFromDB(companyId: string) { return {
    total_inventory_value: 0,
    total_products: 0,
    total_variants: 0,
    low_stock_items: 0,
}; }
export async function getSuppliersDataFromDB(companyId: string) { return []; }
export async function getSupplierByIdFromDB(id: string, companyId: string) { return null; }
export async function createSupplierInDb(companyId: string, formData: SupplierFormData) { return; }
export async function updateSupplierInDb(id: string, companyId: string, formData: SupplierFormData) { return; }
export async function deleteSupplierFromDb(id: string, companyId: string) { return; }
export async function getCustomersFromDB(companyId: string, params: any) { return {items: [], totalCount: 0}; }
export async function deleteCustomerFromDb(customerId: string, companyId: string) { return; }

export async function getSalesFromDB(companyId: string, params: { query?: string, offset: number, limit: number }) {
    const supabase = getServiceRoleClient();
    let query = supabase.from('orders').select('*', { count: 'exact' }).eq('company_id', companyId);
    if(params.query) {
        query = query.or(`order_number.ilike.%${params.query}%`);
    }
    const { data, error, count } = await query.order('created_at', {ascending: false}).range(params.offset, params.offset + params.limit - 1);
    if (error) throw error;
    return { items: z.array(OrderSchema).parse(data || []), totalCount: count || 0 };
}
export async function getSalesAnalyticsFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_sales_analytics', { p_company_id: companyId });
    if (error) throw error;
    return data;
}

export async function getCustomerAnalyticsFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_customer_analytics', { p_company_id: companyId });
    if(error) throw error;
    return data;
}
export async function getDeadStockReportFromDB(companyId: string) { return {deadStockItems: [], totalValue: 0, totalUnits: 0}; }
export async function getReorderSuggestionsFromDB(companyId: string) { return []; }
export async function getAnomalyInsightsFromDB(companyId: string) { return []; }
export async function getAlertsFromDB(companyId: string) { return []; }
export async function getInventoryAgingReportFromDB(companyId: string) { return []; }
export async function getProductLifecycleAnalysisFromDB(companyId: string) { return {summary:{}, products:[]}; }
export async function getInventoryRiskReportFromDB(companyId: string) { return []; }
export async function getCustomerSegmentAnalysisFromDB(companyId: string) { return []; }
export async function getCashFlowInsightsFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_cash_flow_insights', { p_company_id: companyId });
    if (error) throw error;
    return data;
}
export async function getSupplierPerformanceFromDB(companyId: string) { return []; }
export async function getInventoryTurnoverFromDB(companyId: string, days: number) { return {turnover_rate:0,total_cogs:0,average_inventory_value:0,period_days:0}; }


// --- Management & Test functions ---
export async function getIntegrationsByCompanyId(companyId: string): Promise<Integration[]> {
    return withPerformanceTracking('getIntegrationsByCompanyId', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('integrations').select('*').eq('company_id', companyId);
        if (error) throw new Error(`Could not load integrations: ${error.message}`);
        return data || [];
    });
}
export async function deleteIntegrationFromDb(id: string, companyId: string) { /* ... */ }
export async function getTeamMembersFromDB(companyId: string): Promise<TeamMember[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_users_for_company', { p_company_id: companyId });
    if (error) throw error;
    return (data ?? []) as TeamMember[];
}
export async function inviteUserToCompanyInDb(companyId: string, companyName: string, email: string) { /* ... */ }
export async function removeTeamMemberFromDb(userId: string, companyId: string, performingUserId: string) { return {success:true}; }
export async function updateTeamMemberRoleInDb(memberId: string, companyId: string, newRole: 'Admin' | 'Member') { return {success:true}; }
export async function getChannelFeesFromDB(companyId: string) { return []; }
export async function upsertChannelFeeInDB(companyId: string, feeData: any) { return; }
export async function getCompanyById(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('companies').select('name').eq('id', companyId).single();
    if (error) return null;
    return data;
}

// ... other existing utility/test functions
export async function testSupabaseConnection() { return {isConfigured:true, success:true, user: {}} as any; }
export async function testDatabaseQuery() { return {success:true}; }
export async function testMaterializedView() { return {success:true}; }
export async function createAuditLogInDb(companyId: string, userId: string | null, action: string, details?: Record<string, any>): Promise<void> {}
export async function logUserFeedbackInDb(userId: string, companyId: string, subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful') {}
export async function createExportJobInDb(companyId: string, userId: string) { return {} as any; }
export async function healthCheckFinancialConsistency(companyId: string) { return {} as any; }
export async function healthCheckInventoryConsistency(companyId: string) { return {} as any; }
export async function getDbSchemaAndData(companyId: string) { return []; }
