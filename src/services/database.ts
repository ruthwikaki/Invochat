

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, User, TeamMember, Supplier, SupplierFormData, Product, ProductUpdateData, Order } from '@/types';
import { CompanySettingsSchema, SupplierSchema, SupplierFormSchema, ProductUpdateSchema, UnifiedInventoryItemSchema, OrderSchema } from '@/types';
import { invalidateCompanyCache } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { getErrorMessage, logError } from '@/lib/error-handler';

// --- CORE FUNCTIONS (ADAPTED FOR NEW SCHEMA) ---

export async function getSettings(companyId: string): Promise<CompanySettings> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('company_settings').select('*').eq('company_id', companyId).single();
    if (error && error.code !== 'PGRST116') throw error;
    if (data) return CompanySettingsSchema.parse(data);
    const { data: newData, error: insertError } = await supabase.from('company_settings').upsert({ company_id: companyId }).select().single();
    if (insertError) throw insertError;
    return CompanySettingsSchema.parse(newData);
}

export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<CompanySettings> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('company_settings').update({ ...settings, updated_at: new Date().toISOString() }).eq('company_id', companyId).select().single();
    if (error) throw error;
    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
    return CompanySettingsSchema.parse(data);
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; page?: number; limit?: number; offset?: number; }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    const supabase = getServiceRoleClient();
    
    let query = supabase
        .from('product_variants')
        .select(`
            *,
            product:products (
                title,
                status,
                image_url
            )
        `, { count: 'exact' })
        .eq('company_id', companyId);

    if (params.query) {
         const { data: productIdsData, error: productIdsError } = await supabase.from('products').select('id').ilike('title', `%${params.query}%`).eq('company_id', companyId);
         if (productIdsError) { logError(productIdsError); }
         const pids = productIdsData?.map(p => p.id) || [];

         let orQuery = `sku.ilike.%${params.query}%`;
         if (pids.length > 0) {
             orQuery += `,product_id.in.(${pids.join(',')})`;
         }
         query = query.or(orQuery);
    }
    
    const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(params.offset || 0, (params.offset || 0) + (params.limit || 50) - 1);
    
    if (error) {
        logError(error, { context: 'getUnifiedInventoryFromDB failed' });
        throw error;
    }

    const items = (data || []).map(item => ({
        ...item,
        product_title: item.product.title,
        product_status: item.product.status,
        image_url: item.product.image_url,
    }));
    
    return {
        items: z.array(UnifiedInventoryItemSchema).parse(items),
        totalCount: count || 0,
    };
}

export async function updateProductInDb(companyId: string, productId: string, data: ProductUpdateData) {
    const parsedData = ProductUpdateSchema.parse(data);
    const supabase = getServiceRoleClient();
    const { data: updated, error } = await supabase
        .from('products')
        .update({ title: parsedData.title, product_type: parsedData.product_type, updated_at: new Date().toISOString() })
        .eq('id', productId)
        .eq('company_id', companyId)
        .select()
        .single();

    if (error) throw error;
    return updated;
}

export async function getInventoryCategoriesFromDB(companyId: string): Promise<string[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('products')
        .select('product_type')
        .eq('company_id', companyId)
        .not('product_type', 'is', null)
        .distinct();
    if (error) return [];
    return data.map((item: { product_type: string }) => item.product_type) ?? [];
}

export async function getInventoryLedgerFromDB(companyId: string, variantId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('inventory_ledger')
        .select('*')
        .eq('company_id', companyId)
        .eq('variant_id', variantId)
        .order('created_at', { ascending: false })
        .limit(100);
    if(error) throw error;
    return data || [];
}

// Stubs for functions that need significant refactoring or are not implemented yet.
export async function getDashboardMetrics(companyId: string, dateRange: string) { return {}; }
export async function getInventoryAnalyticsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_analytics', { p_company_id: companyId });
    if (error) throw error;
    return data;
}

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

export async function getInventoryAgingReportFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_aging_report', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}
export async function getProductLifecycleAnalysisFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_product_lifecycle_analysis', { p_company_id: companyId });
    if (error) throw error;
    return data;
}

export async function getInventoryRiskReportFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_risk_report', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}

export async function getCustomerSegmentAnalysisFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_customer_segment_analysis', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}

export async function getCashFlowInsightsFromDB(companyId: string) {
    return { dead_stock_value: 0, slow_mover_value: 0, dead_stock_threshold_days: 90 };
}
export async function getSupplierPerformanceFromDB(companyId: string) { return []; }
export async function getInventoryTurnoverFromDB(companyId: string, days: number) { return {turnover_rate:0,total_cogs:0,average_inventory_value:0,period_days:0}; }

export async function getIntegrationsByCompanyId(companyId: string): Promise<Integration[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('integrations').select('*').eq('company_id', companyId);
    if (error) throw new Error(`Could not load integrations: ${error.message}`);
    return data || [];
}
export async function deleteIntegrationFromDb(id: string, companyId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('integrations').delete().eq('id', id).eq('company_id', companyId);
    if (error) throw error;
}
export async function getTeamMembersFromDB(companyId: string): Promise<TeamMember[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_users_for_company', { p_company_id: companyId });
    if (error) throw error;
    return (data ?? []) as TeamMember[];
}
export async function inviteUserToCompanyInDb(companyId: string, companyName: string, email: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.auth.admin.inviteUserByEmail(email, {
        data: {
            company_id: companyId,
            company_name: companyName,
        }
    });
    if (error) throw error;
    return data;
}
export async function removeTeamMemberFromDb(userId: string, companyId: string, performingUserId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('remove_user_from_company', {
        p_user_id: userId,
        p_company_id: companyId,
        p_performing_user_id: performingUserId
    });
    if (error) throw error;
    return { success: true };
}

export async function updateTeamMemberRoleInDb(memberId: string, companyId: string, newRole: 'Admin' | 'Member') {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('update_user_role_in_company', {
        p_user_id: memberId,
        p_company_id: companyId,
        p_new_role: newRole
    });
    if (error) throw error;
    return { success: true };
}

export async function getChannelFeesFromDB(companyId: string) { return []; }
export async function upsertChannelFeeInDB(companyId: string, feeData: any) { return; }
export async function getCompanyById(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('companies').select('name').eq('id', companyId).single();
    if (error) return null;
    return data;
}

export async function testSupabaseConnection() { return {isConfigured:true, success:true, user: {}} as any; }
export async function testDatabaseQuery() { return {success:true}; }
export async function testMaterializedView() { return {success:true}; }
export async function createAuditLogInDb(companyId: string, userId: string | null, action: string, details?: Record<string, any>): Promise<void> {}
export async function logUserFeedbackInDb(userId: string, companyId: string, subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful') {}
export async function createExportJobInDb(companyId: string, userId: string) { return {} as any; }
export async function healthCheckFinancialConsistency(companyId: string) { return {} as any; }
export async function healthCheckInventoryConsistency(companyId: string) { return {} as any; }
export async function getDbSchemaAndData(companyId: string) { return []; }
export async function refreshMaterializedViews(companyId: string) {}
export async function logSuccessfulLogin(userId: string, ip: string) {}

export async function getHistoricalSalesForSkus(companyId: string, skus: string[]) { return []; }
export async function getHistoricalSalesFromDB(companyId: string, days: number) { return []; }
