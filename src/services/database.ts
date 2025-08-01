'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, TeamMember, Supplier, SupplierFormData, Order, DashboardMetrics, ReorderSuggestion, PurchaseOrderWithItems, ChannelFee, Integration, SalesAnalytics, InventoryAnalytics, CustomerAnalytics, PurchaseOrderFormData, AuditLogEntry, FeedbackWithMessages, PurchaseOrderWithItemsAndSupplier, ReorderSuggestionBase } from '@/types';
import { CompanySettingsSchema, SupplierFormSchema, SupplierSchema, UnifiedInventoryItemSchema, OrderSchema, DashboardMetricsSchema, InventoryAnalyticsSchema, SalesAnalyticsSchema, CustomerAnalyticsSchema, DeadStockItemSchema, AuditLogEntrySchema, FeedbackSchema, ReorderSuggestionBaseSchema } from '@/types';
import { isRedisEnabled, redisClient } from '@/lib/redis';
import { z } from 'zod';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { Json } from '@/types/database.types';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { invalidateCompanyCache } from '@/lib/redis';

// --- Input Validation Schemas ---
const DatabaseQueryParamsSchema = z.object({
  query: z.string().optional(),
  page: z.number().min(1).max(1000).optional(),
  limit: z.number().min(1).max(100).optional(),
  offset: z.number().min(0).max(10000).optional(),
  status: z.string().optional(),
  sortBy: z.string().max(50).optional(),
  sortDirection: z.enum(['asc', 'desc']).optional()
});

// --- Authorization Helper ---
/**
 * Checks if a user has the required role to perform an action.
 * Throws an error if the user does not have permission.
 * @param userId The ID of the user to check.
 * @param requiredRole The minimum role required ('Admin' | 'Owner').
 */
export async function checkUserPermission(userId: string, requiredRole: 'Admin' | 'Owner'): Promise<void> {
    if (!userId || !z.string().uuid().safeParse(userId).success) {
        throw new Error('Invalid user ID provided');
    }
    
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('check_user_permission', { 
        p_user_id: userId, 
        p_required_role: requiredRole
    });
    
    if (error) {
        logError(error, { context: 'checkUserPermission RPC failed', userId, requiredRole });
        throw new Error('Could not verify user permissions.');
    }
    
    if (!data) {
        throw new Error('Access Denied: You do not have permission to perform this action.');
    }
}

// --- CORE FUNCTIONS (IMPROVED WITH VALIDATION AND ERROR HANDLING) ---

export async function getSettings(companyId: string): Promise<CompanySettings> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }

    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('company_settings')
        .select('*')
        .eq('company_id', companyId)
        .single();
        
    if (error && error.code !== 'PGRST116') { // PGRST116: no rows found
        logError(error, { context: 'getSettings failed', companyId });
        throw new Error('Failed to retrieve company settings');
    }
    
    if (data) return CompanySettingsSchema.parse(data);
    
    // If no settings exist, create them with default values
    const { data: newData, error: insertError } = await supabase
        .from('company_settings')
        .insert({ company_id: companyId })
        .select()
        .single();
        
    if (insertError) {
        logError(insertError, { context: 'Failed to create default settings', companyId });
        throw new Error(`Failed to create initial company settings: ${insertError.message}`);
    }
    
    return CompanySettingsSchema.parse(newData);
}

export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<{success: boolean, error?: string}> {
    if (!z.string().uuid().safeParse(companyId).success) {
        return { success: false, error: 'Invalid company ID format' };
    }

    try {
        const supabase = getServiceRoleClient();
        const { error } = await supabase
            .from('company_settings')
            .update({ 
                ...settings, 
                updated_at: new Date().toISOString() 
            })
            .eq('company_id', companyId)
            .select()
            .single();
            
        if (error) {
            logError(error, { context: 'updateSettingsInDb failed', companyId });
            return { success: false, error: error.message };
        }
        
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        return { success: true };
    } catch (error) {
        logError(error, { context: 'updateSettingsInDb unexpected error', companyId });
        return { success: false, error: getErrorMessage(error) };
    }
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; page?: number, limit?: number; offset?: number; status?: string; sortBy?: string; sortDirection?: string; }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    try {
        let query = supabase
            .from('product_variants_with_details')
            .select('*', { count: 'exact' })
            .eq('company_id', companyId);

        if (validatedParams.query) {
            const searchTerm = validatedParams.query.replace(/[%_]/g, '\\$&');
            query = query.or(`product_title.ilike.%${searchTerm}%,sku.ilike.%${searchTerm}%`);
        }
        
        if (validatedParams.status && validatedParams.status !== 'all') {
            query = query.eq('product_status', validatedParams.status);
        }

        const limit = Math.min(validatedParams.limit || 50, 100);
        const sortBy = validatedParams.sortBy || 'product_title';
        const sortDirection = validatedParams.sortDirection === 'desc' ? 'desc' : 'asc';
        
        const { data, error, count } = await query
            .order(sortBy, { ascending: sortDirection === 'asc' })
            .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
        
        if (error) {
            logError(error, { context: 'getUnifiedInventoryFromDB query failed', companyId });
            throw new Error('Failed to retrieve inventory data');
        }
        
        return {
            items: z.array(UnifiedInventoryItemSchema).parse(data || []),
            totalCount: count || 0,
        };
    } catch (error) {
        logError(error, { context: 'getUnifiedInventoryFromDB failed', companyId });
        throw error;
    }
}

export async function getInventoryLedgerFromDB(companyId: string, variantId: string) {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    if (!z.string().uuid().safeParse(variantId).success) {
        throw new Error('Invalid variant ID format');
    }

    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('inventory_ledger')
            .select('*')
            .eq('company_id', companyId)
            .eq('variant_id', variantId)
            .order('created_at', { ascending: false })
            .limit(100);
            
        if (error) {
            logError(error, { context: 'getInventoryLedgerFromDB failed', companyId, variantId });
            throw new Error('Failed to retrieve inventory ledger');
        }
        
        return data || [];
    } catch (error) {
        logError(error, { context: 'getInventoryLedgerFromDB unexpected error', companyId, variantId });
        throw error;
    }
}

export async function getDashboardMetrics(companyId: string, period: string | number): Promise<DashboardMetrics> {
    const days = typeof period === 'number' ? period : parseInt(String(period).replace(/\\D/g, ''), 10);
    const supabase = getServiceRoleClient();
    try {
        const { data, error } = await supabase.rpc('get_dashboard_metrics', { p_company_id: companyId, p_days: days });
        if (error) {
            logError(error, { context: 'get_dashboard_metrics failed', companyId, period });
            throw new Error('Could not retrieve dashboard metrics from the database.');
        }
        return DashboardMetricsSchema.parse(data);
    } catch (e) {
        logError(e, { context: 'getDashboardMetrics failed', companyId, period });
        // Return a safe, empty object to prevent frontend crashes
        return {
            total_revenue: 0, revenue_change: 0, total_sales: 0, sales_change: 0, new_customers: 0, customers_change: 0, dead_stock_value: 0, sales_over_time: [], top_selling_products: [],
            inventory_summary: { total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0 },
        };
    }
}


export async function getInventoryAnalyticsFromDB(companyId: string): Promise<InventoryAnalytics> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_inventory_analytics', { p_company_id: companyId });
        if (error) {
            logError(error, { context: 'getInventoryAnalyticsFromDB failed', companyId });
            throw new Error('Failed to retrieve inventory analytics');
        }
        return InventoryAnalyticsSchema.parse(data);
    } catch (error) {
        logError(error, { context: 'getInventoryAnalyticsFromDB unexpected error', companyId });
        throw error;
    }
}

export async function getSuppliersDataFromDB(companyId: string): Promise<Supplier[]> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('suppliers')
            .select('*')
            .eq('company_id', companyId)
            .order('name', { ascending: true });
        if (error) {
            logError(error, { context: 'getSuppliersDataFromDB failed', companyId });
            throw new Error('Failed to retrieve suppliers');
        }
        return z.array(SupplierSchema).parse(data || []);
    } catch (error) {
        logError(error, { context: 'getSuppliersDataFromDB unexpected error', companyId });
        throw error;
    }
}

export async function getSupplierByIdFromDB(id: string, companyId: string) {
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.from('suppliers').select('*').eq('id', id).eq('company_id', companyId).single();
        if (error) {
            if (error.code === 'PGRST116') return null;
            logError(error, { context: 'getSupplierByIdFromDB failed', id, companyId });
            throw new Error('Failed to retrieve supplier');
        }
        return data;
    } catch (error) {
        logError(error, { context: 'getSupplierByIdFromDB unexpected error', id, companyId });
        return null;
    }
}

export async function createSupplierInDb(companyId: string, formData: SupplierFormData) {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    const validatedData = SupplierFormSchema.parse(formData);
    try {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.from('suppliers').insert({ ...validatedData, company_id: companyId });
        if (error) {
            logError(error, { context: 'createSupplierInDb failed', companyId });
            throw new Error('Failed to create supplier');
        }
        await invalidateCompanyCache(companyId, ['suppliers']);
        await refreshMaterializedViews(companyId);
    } catch (error) {
        logError(error, { context: 'createSupplierInDb unexpected error', companyId });
        throw new Error(`Could not create supplier: ${getErrorMessage(error)}`);
    }
}

export async function updateSupplierInDb(id: string, companyId: string, formData: SupplierFormData) { 
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const validatedData = SupplierFormSchema.parse(formData);
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('suppliers').update(validatedData).eq('id', id).eq('company_id', companyId);
    if(error) {
        logError(error, {context: 'updateSupplierInDb failed'});
        throw error;
    }
}

export async function deleteSupplierFromDb(id: string, companyId: string) { 
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('suppliers').delete().eq('id', id).eq('company_id', companyId);
    if(error) {
        logError(error, {context: 'deleteSupplierFromDb failed'});
        throw error;
    }
}

export async function getCustomersFromDB(companyId: string, params: { query?: string, offset: number, limit: number }) { 
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    let query = supabase.from('customers_view').select('*', {count: 'exact'}).eq('company_id', companyId);
    if(validatedParams.query) {
        query = query.or(`customer_name.ilike.%${validatedParams.query}%,email.ilike.%${validatedParams.query}%`);
    }
    const limit = Math.min(validatedParams.limit || 25, 100);
    const { data, error, count } = await query.order('created_at', { ascending: false }).range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
    if(error) throw error;
    return {items: data || [], totalCount: count || 0};
}

export async function deleteCustomerFromDb(customerId: string, companyId: string) {
    if (!z.string().uuid().safeParse(customerId).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('customers').update({ deleted_at: new Date().toISOString() }).eq('id', customerId).eq('company_id', companyId);
    if(error) {
        logError(error, { context: 'Failed to soft-delete customer', customerId });
        throw new Error('Could not delete the customer record.');
    }
}

export async function getSalesFromDB(companyId: string, params: { query?: string; offset: number, limit: number }): Promise<{ items: Order[], totalCount: number }> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    try {
        const supabase = getServiceRoleClient();
        let query = supabase.from('orders_view').select('*', { count: 'exact' }).eq('company_id', companyId);
        if (validatedParams.query) {
            query = query.or(`order_number.ilike.%${validatedParams.query}%,customer_email.ilike.%${validatedParams.query}%`);
        }
        const limit = Math.min(validatedParams.limit || 25, 100);
        const { data, error, count } = await query.order('created_at', { ascending: false }).range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
        if (error) throw error;
        
        return { items: z.array(OrderSchema).parse(data || []), totalCount: count || 0 };
    } catch(e) {
        logError(e, { context: 'getSalesFromDB failed' });
        throw new Error('Failed to retrieve sales data.');
    }
}

export async function getSalesAnalyticsFromDB(companyId: string): Promise<SalesAnalytics> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_sales_analytics', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getSalesAnalyticsFromDB failed' });
        throw error;
    }
    return SalesAnalyticsSchema.parse(data);
}

export async function getCustomerAnalyticsFromDB(companyId: string): Promise<CustomerAnalytics> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_customer_analytics', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getCustomerAnalyticsFromDB failed' });
        throw error;
    }
    return CustomerAnalyticsSchema.parse(data);
}

export async function getDeadStockReportFromDB(companyId: string): Promise<{ deadStockItems: z.infer<typeof DeadStockItemSchema>[], totalValue: number, totalUnits: number }> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_dead_stock_report', { p_company_id: companyId });

    if (error) {
        logError(error, { context: 'getDeadStockReportFromDB failed' });
        return { deadStockItems: [], totalValue: 0, totalUnits: 0 };
    }
    
    const deadStockItems = DeadStockItemSchema.array().parse(data || []);
    
    const totalValue = deadStockItems.reduce((sum, item) => sum + item.total_value, 0);
    const totalUnits = deadStockItems.reduce((sum, item) => sum + item.quantity, 0);
    
    return { deadStockItems, totalValue, totalUnits };
}

export async function getReorderSuggestionsFromDB(companyId: string): Promise<ReorderSuggestionBase[]> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid Company ID');
    }
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_reorder_suggestions', { p_company_id: companyId });

        if (error) {
            logError(error, { context: 'getReorderSuggestionsFromDB failed' });
            throw error;
        }

        return z.array(ReorderSuggestionBaseSchema).parse(data || []);

    } catch (e) {
        logError(e, { context: `Failed to get reorder suggestions for company ${companyId}` });
        throw e;
    }
}

export async function getSupplierPerformanceFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_supplier_performance_report', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getSupplierPerformanceFromDB failed' });
        return [];
    };
    return data || [];
}
export async function getInventoryTurnoverFromDB(companyId: string, days: number) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_inventory_turnover', { p_company_id: companyId, p_days: days });
    if (error) {
        logError(error, { context: 'getInventoryTurnoverFromDB failed, returning null'});
        return null
    };
    return data; 
}

export async function getIntegrationsByCompanyId(companyId: string): Promise<Integration[]> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('integrations').select('*').eq('company_id', companyId);
    if (error) {
        logError(error, { context: 'getIntegrationsByCompanyId failed' });
        return [];
    };
    return (data || []) as Integration[];
}
export async function deleteIntegrationFromDb(id: string, companyId: string) {
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('integrations').delete().eq('id', id).eq('company_id', companyId);
    if (error) throw error;
}
export async function getTeamMembersFromDB(companyId: string): Promise<TeamMember[]> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_users_for_company', { p_company_id: companyId });
    if (error) {
        logError(error, { context: 'getTeamMembersFromDB failed' });
        return [];
    };
    return (data ?? []) as TeamMember[];
}
export async function inviteUserToCompanyInDb(companyId: string, companyName: string, email: string) { 
    if (!z.string().uuid().safeParse(companyId).success || !z.string().email().safeParse(email).success) {
        throw new Error('Invalid input');
    }
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
    if (!z.string().uuid().safeParse(userId).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('remove_user_from_company', {
        p_user_id: userId,
        p_company_id: companyId,
    });
    if (error) throw new Error(error.message);
    return { success: true };
}

export async function updateTeamMemberRoleInDb(memberId: string, companyId: string, newRole: 'Admin' | 'Member' | 'Owner') {
    if (!z.string().uuid().safeParse(memberId).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
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
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('channel_fees').select('*').eq('company_id', companyId);
    if (error) {
        logError(error, { context: 'getChannelFeesFromDB failed' });
        throw error;
    }
    return data || [];
}
export async function upsertChannelFeeInDb(companyId: string, feeData: Partial<ChannelFee>) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const { channel_name } = feeData;
    if (!channel_name) {
        throw new Error("Channel name is required to upsert a fee.");
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('channel_fees').upsert({ ...feeData, company_id: companyId } as any, { onConflict: 'company_id, channel_name' });
    if (error) {
        logError(error, { context: 'upsertChannelFeeInDB failed' });
        throw error;
    }
}
export async function getCompanyById(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) return null;
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

export async function logUserFeedbackInDb(userId: string, companyId: string, subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful') {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('feedback').insert({
        user_id: userId,
        company_id: companyId,
        subject_id: subjectId,
        subject_type: subjectType,
        feedback: feedback,
    });

    if (error) {
        logError(error, { context: 'Failed to log user feedback' });
    }
}
export async function createExportJobInDb(companyId: string, userId: string) { 
    if (!z.string().uuid().safeParse(companyId).success || !z.string().uuid().safeParse(userId).success) throw new Error('Invalid ID format');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('export_jobs').insert({ company_id: companyId, requested_by_user_id: userId }).select().single();
    if (error) throw error;
    return data;
}

export async function refreshMaterializedViews(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) return;
    logger.info(`[DB] Refreshing materialized views for company ${companyId}`);
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('refresh_all_matviews', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'Failed to refresh materialized views', companyId });
    } else {
        logger.info(`[DB] Successfully refreshed materialized views for company ${companyId}`);
    }
}

export async function getHistoricalSalesForSkus(companyId: string, skus: string[]) {
    if (!z.string().uuid().safeParse(companyId).success) return [];
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_historical_sales_for_skus', { p_company_id: companyId, p_skus: skus });
    if (error) {
        logError(error, { context: `Failed to get historical sales for SKUs`, skus });
        return [];
    }
    return data || [];
}

export async function reconcileInventoryInDb(companyId: string, integrationId: string, userId: string) {
    if (!z.string().uuid().safeParse(companyId).success || !z.string().uuid().safeParse(integrationId).success || !z.string().uuid().safeParse(userId).success) throw new Error('Invalid ID format');
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('reconcile_inventory_from_integration', { p_company_id: companyId, p_integration_id: integrationId, p_user_id: userId });
    if(error) throw error;
}

export async function createPurchaseOrderInDb(companyId: string, userId: string, poData: PurchaseOrderFormData) {
    if (!z.string().uuid().safeParse(companyId).success || !z.string().uuid().safeParse(userId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('create_full_purchase_order', {
        p_company_id: companyId,
        p_user_id: userId,
        p_supplier_id: poData.supplier_id,
        p_status: poData.status,
        p_notes: poData.notes,
        p_expected_arrival: poData.expected_arrival_date,
        p_line_items: poData.line_items,
    }).select('id').single();

    if (error) {
        logError(error, { context: 'Failed to execute create_full_purchase_order RPC' });
        throw new Error('Database error while creating purchase order.');
    }
    
    return data.id;
}

export async function updatePurchaseOrderInDb(poId: string, companyId: string, userId: string, poData: PurchaseOrderFormData) {
    if (!z.string().uuid().safeParse(poId).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('update_full_purchase_order', {
        p_po_id: poId,
        p_company_id: companyId,
        p_user_id: userId,
        p_supplier_id: poData.supplier_id,
        p_status: poData.status,
        p_notes: poData.notes,
        p_expected_arrival: poData.expected_arrival_date,
        p_line_items: poData.line_items,
    });

    if (error) {
        logError(error, { context: 'Failed to execute update_full_purchase_order RPC' });
        throw new Error('Database error while updating purchase order.');
    }
    
    return data;
}

export async function getPurchaseOrdersFromDB(companyId: string): Promise<PurchaseOrderWithItemsAndSupplier[]> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('purchase_orders_view')
        .select('*')
        .eq('company_id', companyId)
        .order('created_at', { ascending: false });

    if (error) {
        logError(error, { context: 'Failed to fetch purchase orders' });
        throw error;
    }
    
    return (data || []) as PurchaseOrderWithItemsAndSupplier[];
}

export async function getPurchaseOrderByIdFromDB(id: string, companyId: string) {
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('purchase_orders_view').select('*').eq('id', id).eq('company_id', companyId).single();

    if (error) {
        if(error.code === 'PGRST116') return null;
        logError(error, { context: 'getPurchaseOrderByIdFromDB failed' });
        throw new Error('Failed to retrieve purchase order');
    }
    return data as PurchaseOrderWithItemsAndSupplier;
}

export async function deletePurchaseOrderFromDb(id: string, companyId: string) {
    if (!z.string().uuid().safeParse(id).success || !z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('purchase_orders').delete().eq('id', id).eq('company_id', companyId);
    if(error) {
        logError(error, { context: 'Failed to delete purchase order', id });
        throw error;
    }
}


export async function getHistoricalSalesForSingleSkuFromDB(companyId: string, sku: string): Promise<{ sale_date: string; total_quantity: number }[]> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_historical_sales_for_sku', {
        p_company_id: companyId,
        p_sku: sku,
    });
    if (error) {
        logError(error, { context: 'Failed to get historical sales for single SKU' });
        return [];
    }
    return data || [];
}

export async function logWebhookEvent(integrationId: string, webhookId: string) {
    if (!z.string().uuid().safeParse(integrationId).success) throw new Error('Invalid Integration ID');
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('webhook_events').insert({
        integration_id: integrationId,
        webhook_id: webhookId
    });

    if (error) {
        if (error.code === '23505') {
            return { success: false, error: 'Duplicate webhook event' };
        }
        logError(error, { context: 'Failed to log webhook event' });
    }
    return { success: true };
}

export async function getNetMarginByChannelFromDB(companyId: string, channelName: string) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_net_margin_by_channel', { p_company_id: companyId, p_channel_name: channelName });
    if(error) {
        logError(error, { context: 'getNetMarginByChannelFromDB failed' });
        return null;
    }
    return data; 
}
export async function getSalesVelocityFromDB(companyId: string, days: number, limit: number) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_sales_velocity', { p_company_id: companyId, p_days: days, p_limit: limit });
    if(error) {
        logError(error, { context: 'getSalesVelocityFromDB failed' });
        return { fast_sellers: [], slow_sellers: [] };
    }
    return data; 
}
export async function getDemandForecastFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('forecast_demand', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getDemandForecastFromDB failed' });
        return null;
    }
    return data; 
}
export async function getAbcAnalysisFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_abc_analysis', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getAbcAnalysisFromDB failed' });
        return [];
    }
    return data; 
}
export async function getGrossMarginAnalysisFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_gross_margin_analysis', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getGrossMarginAnalysisFromDB failed' });
        return { products: [], summary: { total_revenue: 0, total_cogs: 0, total_gross_margin: 0, average_gross_margin: 0 } };
    }
    return data; 
}
export async function getMarginTrendsFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_margin_trends', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getMarginTrendsFromDB failed' });
        return null;
    }
    return data; 
}
export async function getFinancialImpactOfPromotionFromDB(companyId: string, skus: string[], discount: number, duration: number) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_financial_impact_of_promotion', { p_company_id: companyId, p_skus: skus, p_discount_percentage: discount, p_duration_days: duration });
    if(error) {
        logError(error, { context: 'getFinancialImpactOfPromotionFromDB failed' });
        return null;
    }
    return data; 
}

export async function adjustInventoryQuantityInDb(companyId: string, userId: string, variantId: string, newQuantity: number, reason: string) {
    if (!z.string().uuid().safeParse(companyId).success || !z.string().uuid().safeParse(variantId).success || !z.string().uuid().safeParse(userId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { error } = await supabase.rpc('adjust_inventory_quantity', {
        p_company_id: companyId,
        p_variant_id: variantId,
        p_new_quantity: newQuantity,
        p_change_reason: reason,
        p_user_id: userId
    });

    if(error) {
        logError(error, { context: `Failed to adjust inventory for variant ${variantId}`});
        throw error;
    }
}

export async function getAuditLogFromDB(companyId: string, params: { query?: string; offset: number; limit: number }): Promise<{ items: AuditLogEntry[], totalCount: number }> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    try {
        let query = supabase.from('audit_log_view').select('*', { count: 'exact' }).eq('company_id', companyId);
        if (validatedParams.query) {
            query = query.or(`action.ilike.%${validatedParams.query}%,user_email.ilike.%${validatedParams.query}%`);
        }
        const limit = Math.min(validatedParams.limit || 25, 100);
        const { data, error, count } = await query
            .order('created_at', { ascending: false })
            .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
            
        if (error) throw error;
        
        return {
            items: z.array(AuditLogEntrySchema).parse(data || []),
            totalCount: count || 0,
        };
    } catch(e) {
        logError(e, { context: 'getAuditLogFromDB failed' });
        return { items: [], totalCount: 0 };
    }
}

export async function getFeedbackFromDB(companyId: string, params: { query?: string, offset: number, limit: number }): Promise<{ items: FeedbackWithMessages[], totalCount: number }> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    try {
        let query = supabase.from('feedback_view').select('*', { count: 'exact' }).eq('company_id', companyId);

        if (validatedParams.query) {
            query = query.or(`user_email.ilike.%${validatedParams.query}%,user_message_content.ilike.%${validatedParams.query}%,assistant_message_content.ilike.%${validatedParams.query}%`);
        }

        const limit = Math.min(validatedParams.limit || 25, 100);
        const { data, error, count } = await query
            .order('created_at', { ascending: false })
            .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);

        if (error) throw error;

        return {
            items: z.array(FeedbackSchema).parse(data || []),
            totalCount: count || 0
        };
    } catch (e) {
        logError(e, { context: 'getFeedbackFromDB failed' });
        return { items: [], totalCount: 0 };
    }
}

export async function createPurchaseOrdersFromSuggestionsInDb(companyId: string, userId: string, suggestions: ReorderSuggestion[]): Promise<number> {
    if (!z.string().uuid().safeParse(companyId).success || !z.string().uuid().safeParse(userId).success) {
        throw new Error('Invalid ID format');
    }
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('create_purchase_orders_from_suggestions', {
        p_company_id: companyId,
        p_user_id: userId,
        p_suggestions: suggestions as unknown as Json,
    });

    if (error) {
        logError(error, { context: 'Failed to execute create_purchase_orders_from_suggestions RPC' });
        throw new Error('Database error while creating purchase orders from suggestions.');
    }
    
    return data;
}
