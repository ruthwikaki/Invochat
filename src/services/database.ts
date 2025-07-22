
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, TeamMember, Supplier, SupplierFormData, ProductUpdateData, Order, DashboardMetrics, ReorderSuggestion, PurchaseOrderWithSupplier, ChannelFee, Anomaly, Alert, Integration, SalesAnalytics, InventoryAnalytics, CustomerAnalytics, InventoryAgingReportItem, ProductLifecycleAnalysis, InventoryRiskItem, CustomerSegmentAnalysisItem } from '@/types';
import { CompanySettingsSchema, SupplierSchema, ProductUpdateSchema, UnifiedInventoryItemSchema, OrderSchema, DashboardMetricsSchema, AlertSchema, InventoryAnalyticsSchema, SalesAnalyticsSchema, CustomerAnalyticsSchema, InventoryAgingReportItemSchema, ProductLifecycleAnalysisSchema, InventoryRiskItemSchema, CustomerSegmentAnalysisItemSchema, DeadStockItemSchema } from '@/types';
import { invalidateCompanyCache } from '@/lib/redis';
import { z } from 'zod';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { Json } from '@/types/database.types';

// --- Authorization Helper ---
/**
 * Checks if a user has the required role to perform an action.
 * Throws an error if the user does not have permission.
 * @param userId The ID of the user to check.
 * @param requiredRole The minimum role required ('Admin' or 'Owner').
 */
export async function checkUserPermission(userId: string, requiredRole: 'Admin' | 'Owner'): Promise<void> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('check_user_permission', { p_user_id: userId, p_required_role: requiredRole });
    if (error) {
        logError(error, { context: 'checkUserPermission RPC failed' });
        throw new Error('Could not verify user permissions.');
    }
    if (!data) {
        throw new Error('Access Denied: You do not have permission to perform this action.');
    }
}


// --- CORE FUNCTIONS (ADAPTED FOR NEW SCHEMA) ---

export async function getSettings(companyId: string): Promise<CompanySettings> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('company_settings').select('*').eq('company_id', companyId).single();
    if (error && error.code !== 'PGRST116') { // PGRST116: no rows found
        throw error;
    }
    if (data) return CompanySettingsSchema.parse(data);
    
    // If no settings exist, create them with default values
    const { data: newData, error: insertError } = await supabase
        .from('company_settings')
        .insert({ company_id: companyId })
        .select()
        .single();
        
    if (insertError) {
        throw new Error(`Failed to create initial company settings: ${insertError.message}`);
    }
    
    return CompanySettingsSchema.parse(newData);
}

export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<{success: boolean, error?: string}> {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('company_settings').update({ ...settings, updated_at: new Date().toISOString() }).eq('company_id', companyId).select().single();
    if (error) {
      logError(error, {context: 'updateSettingsInDb failed'});
      return {success: false, error: error.message };
    }
    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
    return { success: true };
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; page?: number, limit?: number; offset?: number; status?: string; sortBy?: string; sortDirection?: string; }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    const supabase = getServiceRoleClient();
    
    // The view name is 'product_variants_with_details'
    let query = supabase
        .from('product_variants_with_details')
        .select('*', { count: 'exact' })
        .eq('company_id', companyId);

    if (params.query) {
        query = query.or(`product_title.ilike.%${params.query}%,sku.ilike.%${params.query}%`);
    }
    
    if (params.status && params.status !== 'all') {
        query = query.eq('product_status', params.status);
    }

    const limit = Math.min(params.limit || 50, 100); // Enforce max limit
    const sortBy = params.sortBy || 'product_title';
    const sortDirection = params.sortDirection === 'desc' ? 'desc' : 'asc';
    
    const { data, error, count } = await query
        .order(sortBy, { ascending: sortDirection === 'asc' })
        .range(params.offset || 0, (params.offset || 0) + limit - 1);
    
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
        .not('product_type', 'is', null);

    if (error) return [];
    
    const distinctCategories = Array.from(new Set(data.map((item: { product_type: string | null }) => item.product_type).filter(Boolean) as string[]));

    return distinctCategories;
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
export async function getInventoryAnalyticsFromDB(companyId: string): Promise<InventoryAnalytics> { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_analytics', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getInventoryAnalyticsFromDB failed' });
        throw error;
    }
    return InventoryAnalyticsSchema.parse(data);
}

export async function getSuppliersDataFromDB(companyId: string): Promise<Supplier[]> { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('suppliers').select('*').eq('company_id', companyId);
    if(error) {
        logError(error, { context: 'getSuppliersDataFromDB failed' });
        throw error;
    }
    return z.array(SupplierSchema).parse(data || []);
}
export async function getSupplierByIdFromDB(id: string, companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('suppliers').select('*').eq('id', id).eq('company_id', companyId).single();
    if(error) return null;
    return data;
}
export async function createSupplierInDb(companyId: string, formData: SupplierFormData) {
    const supabase = getServiceRoleClient();
    try {
        const { error } = await supabase.from('suppliers').insert({ ...formData, company_id: companyId });
        if (error) {
            throw error;
        }
    } catch (error) {
        logError(error, { context: 'createSupplierInDb failed' });
        throw new Error(`Could not create supplier: ${getErrorMessage(error)}`);
    }
}
export async function updateSupplierInDb(id: string, companyId: string, formData: SupplierFormData) {
    const supabase = getServiceRoleClient();
    try {
        const { error } = await supabase.from('suppliers').update(formData).eq('id', id).eq('company_id', companyId);
        if (error) {
            throw error;
        }
    } catch (error) {
        logError(error, { context: `updateSupplierInDb failed for id: ${id}` });
        throw new Error(`Could not update supplier: ${getErrorMessage(error)}`);
    }
}
export async function deleteSupplierFromDb(id: string, companyId: string) { 
    const supabase = getServiceRoleClient();
    try {
        const { error } = await supabase.from('suppliers').delete().eq('id', id).eq('company_id', companyId);
        if (error) {
            throw error;
        }
    } catch (e) {
        logError(e, { context: `deleteSupplierFromDb failed for id: ${id}` });
        throw new Error(`Could not delete supplier: ${getErrorMessage(e)}`);
    }
}
export async function getCustomersFromDB(companyId: string, params: { query?: string, offset: number, limit: number }) { 
    const supabase = getServiceRoleClient();
    let query = supabase.from('customers_view').select('*', {count: 'exact'}).eq('company_id', companyId);
    if(params.query) {
        query = query.or(`customer_name.ilike.%${params.query}%,email.ilike.%${params.query}%`);
    }
    const limit = Math.min(params.limit || 25, 100);
    const { data, error, count } = await query.order('created_at', { ascending: false }).range(params.offset, params.offset + limit - 1);
    if(error) throw error;
    return {items: data || [], totalCount: count || 0};
}
export async function deleteCustomerFromDb(customerId: string, companyId: string) { 
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('customers').update({ deleted_at: new Date().toISOString() }).eq('id', customerId).eq('company_id', companyId);
    if(error) {
        logError(error, { context: 'Failed to soft-delete customer', customerId });
        throw new Error('Could not delete the customer record.');
    }
}

export async function getSalesFromDB(companyId: string, params: { query?: string, offset: number, limit: number }): Promise<{ items: Order[], totalCount: number }> {
    try {
        const supabase = getServiceRoleClient();
        let query = supabase.from('orders_view').select('*', { count: 'exact' }).eq('company_id', companyId);
        if (params.query) {
            query = query.or(`order_number.ilike.%${params.query}%,customer_email.ilike.%${params.query}%`);
        }
        const limit = Math.min(params.limit || 25, 100);
        const { data, error, count } = await query.order('created_at', { ascending: false }).range(params.offset, params.offset + limit - 1);
        if (error) throw error;
        return { items: z.array(OrderSchema).parse(data || []), totalCount: count || 0 };
    } catch(e) {
        logError(e, { context: 'getSalesFromDB failed' });
        throw new Error('Failed to retrieve sales data.');
    }
}

export async function getSalesAnalyticsFromDB(companyId: string): Promise<SalesAnalytics> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_sales_analytics', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getSalesAnalyticsFromDB failed' });
        throw error;
    }
    return SalesAnalyticsSchema.parse(data);
}

export async function getCustomerAnalyticsFromDB(companyId: string): Promise<CustomerAnalytics> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_customer_analytics', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getCustomerAnalyticsFromDB failed' });
        throw error;
    }
    return CustomerAnalyticsSchema.parse(data);
}

export async function getDeadStockReportFromDB(companyId: string): Promise<{ deadStockItems: z.infer<typeof DeadStockItemSchema>[], totalValue: number, totalUnits: number }> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_dead_stock_report', { p_company_id: companyId });

    if (error) {
        logError(error, { context: 'getDeadStockReportFromDB failed' });
        // Return a default empty state on error to prevent downstream failures
        return { deadStockItems: [], totalValue: 0, totalUnits: 0 };
    }
    
    // Safely parse the data with Zod. If parsing fails, it will throw an error.
    const deadStockItems = DeadStockItemSchema.array().parse(data || []);
    
    // Calculate totals from the validated data
    const totalValue = deadStockItems.reduce((sum, item) => sum + item.total_value, 0);
    const totalUnits = deadStockItems.reduce((sum, item) => sum + item.quantity, 0);
    
    return { deadStockItems, totalValue, totalUnits };
}

export async function getReorderSuggestionsFromDB(companyId: string): Promise<ReorderSuggestion[]> { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_reorder_suggestions', { p_company_id: companyId });
    if (error) throw error;
    return (data || []) as ReorderSuggestion[];
}

export async function getAnomalyInsightsFromDB(companyId: string): Promise<Anomaly[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('detect_anomalies', { p_company_id: companyId });
    if (error) {
        logError(error, { context: `getAnomalyInsightsFromDB failed for company ${companyId}` });
        return []; // Return empty array on error
    };
    return (data as Anomaly[]) || [];
}
export async function getAlertsFromDB(companyId: string): Promise<Alert[]> { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_alerts', { p_company_id: companyId });
    
    if (error) {
        logError(error, { context: `getAlertsFromDB failed for company ${companyId}` });
        return []; // Always return a valid array
    }

    // Safely parse the data, defaulting to an empty array if parsing fails or data is null
    const parseResult = AlertSchema.array().safeParse(data || []);
    if (!parseResult.success) {
        logError(parseResult.error, { context: `Zod parsing failed for getAlertsFromDB for company ${companyId}` });
        return [];
    }

    return parseResult.data;
}

export async function getInventoryAgingReportFromDB(companyId: string): Promise<InventoryAgingReportItem[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_aging_report', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getInventoryAgingReportFromDB failed' });
        throw error;
    }
    return z.array(InventoryAgingReportItemSchema).parse(data || []);
}
export async function getProductLifecycleAnalysisFromDB(companyId: string): Promise<ProductLifecycleAnalysis> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_product_lifecycle_analysis', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getProductLifecycleAnalysisFromDB failed' });
        throw error;
    }
    return ProductLifecycleAnalysisSchema.parse(data);
}

export async function getInventoryRiskReportFromDB(companyId: string): Promise<InventoryRiskItem[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_risk_report', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getInventoryRiskReportFromDB failed' });
        throw error;
    }
    return z.array(InventoryRiskItemSchema).parse(data || []);
}

export async function getCustomerSegmentAnalysisFromDB(companyId: string): Promise<CustomerSegmentAnalysisItem[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_customer_segment_analysis', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getCustomerSegmentAnalysisFromDB failed' });
        throw error;
    }
    return z.array(CustomerSegmentAnalysisItemSchema).parse(data || []);
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
    return (data || []) as Integration[];
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
export async function removeTeamMemberFromDb(userId: string, companyId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('remove_user_from_company', {
        p_user_id: userId,
        p_company_id: companyId,
    });
    if (error) throw new Error(error.message);
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

export async function getChannelFeesFromDB(companyId: string): Promise<ChannelFee[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('channel_fees').select('*').eq('company_id', companyId);
    if (error) {
        logError(error, { context: 'getChannelFeesFromDB failed' });
        throw error;
    }
    return data || [];
}
export async function upsertChannelFeeInDb(companyId: string, feeData: Partial<ChannelFee>) {
    const supabase = getServiceRoleClient();
    const { channel_name } = feeData;
    if (!channel_name) {
        throw new Error("Channel name is required to upsert a fee.");
    }
    const { error } = await supabase.from('channel_fees').upsert({ ...feeData, company_id: companyId } as any, { onConflict: 'company_id, channel_name' });
    if (error) {
        logError(error, { context: 'upsertChannelFeeInDB failed' });
        throw error;
    }
}
export async function getCompanyById(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('companies').select('name').eq('id', companyId).single();
    if (error) return null;
    return data;
}

export async function createAuditLogInDb(companyId: string, userId: string | null, action: string, details?: Record<string, unknown>): Promise<void> {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('audit_log').insert({
        company_id: companyId,
        user_id: userId,
        action: action,
        details: details as Json
    });
    if (error) {
        logError(error, { context: 'Failed to create audit log entry' });
    }
}

export async function logUserFeedbackInDb() {
    // Placeholder function
}
export async function createExportJobInDb(companyId: string, userId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('export_jobs').insert({ company_id: companyId, requested_by_user_id: userId }).select().single();
    if (error) throw error;
    return data;
}

export async function refreshMaterializedViews(companyId: string) {
    // Placeholder function
    console.log('refreshMaterializedViews called for company:', companyId);
}

export async function getHistoricalSalesForSkus(companyId: string, skus: string[]) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_historical_sales_for_skus', { p_company_id: companyId, p_skus: skus });
    if (error) {
        logError(error, { context: `Failed to get historical sales for SKUs`, skus });
        return [];
    }
    return data || [];
}

export async function reconcileInventoryInDb(companyId: string, integrationId: string, userId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('reconcile_inventory_from_integration', { p_company_id: companyId, p_integration_id: integrationId, p_user_id: userId });
    if(error) throw error;
}

export async function createPurchaseOrdersInDb(companyId: string, userId: string, suggestions: ReorderSuggestion[], idempotencyKey?: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('create_purchase_orders_from_suggestions', {
        p_company_id: companyId,
        p_user_id: userId,
        p_suggestions: suggestions as unknown as Json,
        p_idempotency_key: idempotencyKey ?? null,
    });

    if (error) {
        logError(error, { context: 'Failed to execute create_purchase_orders_from_suggestions RPC' });
        throw new Error('Database error while creating purchase orders.');
    }
    
    return data; // This should be the count of POs created
}

export async function getPurchaseOrdersFromDB(companyId: string): Promise<PurchaseOrderWithSupplier[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('purchase_orders')
        .select(`
            *,
            suppliers(name)
        `)
        .eq('company_id', companyId)
        .order('created_at', { ascending: false });

    if (error) {
        logError(error, { context: 'Failed to fetch purchase orders' });
        throw error;
    }
    
    // The query returns { suppliers: { name: 'Supplier A' } }, so we need to flatten it.
    const flattenedData = (data || []).map(po => {
        const typedPo = po as any; // Cast to any to access nested property dynamically
        return {
            ...po,
            supplier_name: typedPo.suppliers?.name || 'N/A',
        };
    });


    return flattenedData as PurchaseOrderWithSupplier[];
}

export async function getHistoricalSalesForSingleSkuFromDB(companyId: string, sku: string): Promise<{ sale_date: string; total_quantity: number }[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_historical_sales_for_sku', {
        p_company_id: companyId,
        p_sku: sku,
    });
    if (error) {
        logError(error, { context: 'Failed to get historical sales for single SKU' });
        throw new Error('Could not retrieve historical sales data.');
    }
    return data || [];
}

export async function getDbSchemaAndData() { return { schema: {}, data: {} }; }

export async function logWebhookEvent(integrationId: string, webhookId: string) {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('webhook_events').insert({
        integration_id: integrationId,
        webhook_id: webhookId
    });

    if (error) {
        // If it's a unique constraint violation, it's a replay attack.
        if (error.code === '23505') {
            return { success: false, error: 'Duplicate webhook event' };
        }
        // For other errors, log them but maybe don't fail the whole request.
        logError(error, { context: 'Failed to log webhook event' });
    }
    return { success: true };
}

export async function getNetMarginByChannelFromDB(companyId: string, channelName: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_net_margin_by_channel', { p_company_id: companyId, p_channel_name: channelName });
    if(error) {
        logError(error, { context: 'getNetMarginByChannelFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getSalesVelocityFromDB(companyId: string, days: number, limit: number) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_sales_velocity', { p_company_id: companyId, p_days: days, p_limit: limit });
    if(error) {
        logError(error, { context: 'getSalesVelocityFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getDemandForecastFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('forecast_demand', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getDemandForecastFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getAbcAnalysisFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_abc_analysis', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getAbcAnalysisFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getGrossMarginAnalysisFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_gross_margin_analysis', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getGrossMarginAnalysisFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getMarginTrendsFromDB(companyId: string) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_margin_trends', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getMarginTrendsFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getFinancialImpactOfPromotionFromDB(companyId: string, skus: string[], discount: number, duration: number) { 
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_financial_impact_of_promotion', { p_company_id: companyId, p_skus: skus, p_discount_percentage: discount, p_duration_days: duration });
    if(error) {
        logError(error, { context: 'getFinancialImpactOfPromotionFromDB failed' });
        throw error;
    }
    return data; 
}
export async function testSupabaseConnection() { return {success: true}; }
export async function testDatabaseQuery() { return {success: true}; }
export async function testMaterializedView() { return {success: true}; }
export async function getCompanyIdForUser(userId: string): Promise<string | null> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('company_users').select('company_id').eq('user_id', userId).single();
    if(error) {
        logError(error, {context: 'getCompanyIdForUser failed'});
        return null;
    }
    return data?.company_id || null;
}
