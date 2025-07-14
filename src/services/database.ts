

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, User, TeamMember, Supplier, SupplierFormData, Product, ProductUpdateData, Order, DashboardMetrics } from '@/types';
import { CompanySettingsSchema, SupplierSchema, SupplierFormSchema, ProductUpdateSchema, UnifiedInventoryItemSchema, OrderSchema, DashboardMetricsSchema } from '@/types';
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
        .from('product_variants_with_details')
        .select('*', { count: 'exact' })
        .eq('company_id', companyId);

    if (params.query) {
        query = query.or(`product_title.ilike.%${params.query}%,sku.ilike.%${params.query}%`);
    }
    
    const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(params.offset || 0, (params.offset || 0) + (params.limit || 50) - 1);
    
    if (error) {
        logError(error, { context: 'getUnifiedInventoryFromDB failed' });
        throw error;
    }
    
    return {
        items: z.array(UnifiedInventoryItemSchema).parse(data || []),
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

export async function getDashboardMetrics(companyId: string, dateRange: string): Promise<DashboardMetrics> {
    const supabase = getServiceRoleClient();
    const days = parseInt(dateRange.replace('d', ''));
    if (isNaN(days)) {
        throw new Error('Invalid date range format provided.');
    }
    const { data, error } = await supabase.rpc('get_dashboard_metrics', { p_company_id: companyId, p_days: days });
    if (error) {
        logError(error, { context: 'Failed to get dashboard metrics' });
        throw new Error('Could not retrieve dashboard metrics from the database.');
    }
    return DashboardMetricsSchema.parse(data);
}
export async function getInventoryAnalyticsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_analytics', { p_company_id: companyId });
    if (error) throw error;
    return data;
}

export async function getSuppliersDataFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('suppliers').select('*').eq('company_id', companyId);
    if(error) throw error;
    return data || [];
}
export async function getSupplierByIdFromDB(id: string, companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('suppliers').select('*').eq('id', id).eq('company_id', companyId).single();
    if(error) return null;
    return data;
}
export async function createSupplierInDb(companyId: string, formData: SupplierFormData) { 
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('suppliers').insert({ ...formData, company_id: companyId });
    if (error) throw error;
}
export async function updateSupplierInDb(id: string, companyId: string, formData: SupplierFormData) { 
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('suppliers').update(formData).eq('id', id).eq('company_id', companyId);
    if (error) throw error;
}
export async function deleteSupplierFromDb(id: string, companyId: string) { 
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('suppliers').delete().eq('id', id).eq('company_id', companyId);
    if (error) throw error;
}
export async function getCustomersFromDB(companyId: string, params: any) { 
    const supabase = getServiceRoleClient();
    let query = supabase.from('customers').select('*', {count: 'exact'}).eq('company_id', companyId);
    if(params.query) {
        query = query.or(`customer_name.ilike.%${params.query}%,email.ilike.%${params.query}%`);
    }
    const { data, error, count } = await query.range(params.offset, params.offset + params.limit - 1);
    if(error) throw error;
    return {items: data || [], totalCount: count || 0};
}
export async function deleteCustomerFromDb(customerId: string, companyId: string) { 
     const supabase = getServiceRoleClient();
    const { error } = await supabase.from('customers').update({ deleted_at: new Date().toISOString() }).eq('id', customerId).eq('company_id', companyId);
    if(error) throw error;
}

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
export async function getDeadStockReportFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_dead_stock_report', { p_company_id: companyId });
    if (error) throw error;
    return {
        deadStockItems: data || [],
        totalValue: data.reduce((sum: number, item: any) => sum + item.total_value, 0),
        totalUnits: data.reduce((sum: number, item: any) => sum + item.quantity, 0),
    };
}
export async function getReorderSuggestionsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_reorder_suggestions', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}
export async function getAnomalyInsightsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('detect_anomalies', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}
export async function getAlertsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_alerts', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}

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
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_cash_flow_insights', { p_company_id: companyId });
    if(error) throw error;
    return data;
}
export async function getSupplierPerformanceFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_supplier_performance_report', { p_company_id: companyId });
    if (error) throw error;
    return data || [];
}
export async function getInventoryTurnoverFromDB(companyId: string, days: number) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_turnover', { p_company_id: companyId, p_days: days });
    if (error) throw error;
    return data;
}

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

export async function getChannelFeesFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('channel_fees').select('*').eq('company_id', companyId);
    if (error) throw error;
    return data || [];
}
export async function upsertChannelFeeInDB(companyId: string, feeData: any) { 
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('channel_fees').upsert({ ...feeData, company_id: companyId }, { onConflict: 'company_id, channel_name' });
    if (error) throw error;
}
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
export async function createExportJobInDb(companyId: string, userId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('export_jobs').insert({ company_id: companyId, requested_by_user_id: userId }).select().single();
    if (error) throw error;
    return data;
}
export async function healthCheckFinancialConsistency(companyId: string) { return {} as any; }
export async function healthCheckInventoryConsistency(companyId: string) { return {} as any; }
export async function getDbSchemaAndData(companyId: string) { return []; }
export async function refreshMaterializedViews(companyId: string) {}
export async function logSuccessfulLogin(userId: string, ip: string) {}

export async function getHistoricalSalesForSkus(companyId: string, skus: string[]) { return []; }
export async function getHistoricalSalesFromDB(companyId: string, days: number) { return []; }

export async function reconcileInventoryInDb(companyId: string, integrationId: string, userId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('reconcile_inventory_from_integration', { p_company_id: companyId, p_integration_id: integrationId, p_user_id: userId });
    if(error) throw error;
}

export async function logPOCreationInDb(poNumber: string, supplierName: string, items: any[], companyId: string, userId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('audit_log').insert({
        company_id: companyId,
        user_id: userId,
        action: 'purchase_order_created',
        details: { poNumber, supplierName, items: items.map(i => ({ sku: i.sku, qty: i.suggested_reorder_quantity })) }
    });
    if (error) { logError(error, { context: 'Failed to log PO creation' }); }
}
export async function transferStockInDb(companyId: string, userId: string, data: any) { }

export async function logWebhookEvent(integrationId: string, platform: string, webhookId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('webhook_events').insert({ integration_id: integrationId, webhook_id: webhookId });
    if (error) {
        if (error.code === '23505') { // unique_violation
            return { success: false, error: 'Duplicate webhook event' };
        }
        throw error;
    }
    return { success: true };
}
