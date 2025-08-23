
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { CompanySettings, UnifiedInventoryItem, TeamMember, Supplier, PurchaseOrderFormData, ChannelFee, Integration, SalesAnalytics, CustomerAnalytics, ReorderSuggestion, PurchaseOrderWithItemsAndSupplier, AuditLogEntry, FeedbackWithMessages, DashboardMetrics, InventoryAnalytics, SupplierFormData, Order } from '@/types';
import { CompanySettingsSchema, SupplierSchema, UnifiedInventoryItemSchema, OrderSchema, DeadStockItemSchema, AuditLogEntrySchema, FeedbackSchema, SupplierPerformanceReportSchema, ReorderSuggestionSchema, SalesAnalyticsSchema, CustomerAnalyticsSchema, InventoryAnalyticsSchema, SupplierFormSchema, DashboardMetricsSchema } from '@/types';
import { z } from 'zod';
import { getErrorMessage, logError } from '@/lib/error-handler';
import type { Json } from '@/types/database.types';
import { logger } from '@/lib/logger';
// import { isRedisEnabled, redisClient } from '@/lib/redis';
// import { config } from '@/config/app-config';

// Re-export the getServiceRoleClient function
export { getServiceRoleClient };

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

// --- Caching Helper ---
// async function getCachedData<T>(key: string, fetchFn: () => Promise<T>, ttl: number = config.redis.ttl.dashboard): Promise<T> {
//   if (isRedisEnabled) {
//     try {
//       const cached = await redisClient.get(key);
//       if (cached) {
//         logger.debug(`[Cache] HIT for key: ${key}`);
//         return JSON.parse(cached);
//       }
//     } catch (error) {
//       logError(error, { context: `Redis cache read failed for key: ${key}`});
//     }
//   }
//   
//   logger.debug(`[Cache] MISS for key: ${key}`);
//   const data = await fetchFn();
//   
//   if (isRedisEnabled) {
//     try {
//       await redisClient.setex(key, ttl, JSON.stringify(data));
//     } catch (error) {
//       logError(error, { context: `Redis cache write failed for key: ${key}`});
//     }
//   }
// 
//   return data;
// }


// --- Authorization Helper ---
/**
 * Checks if a user has the required role to perform an action.
 * Throws an error if the user does not have permission.
 * @param userId The ID of the user to check.
 * @param requiredRole The minimum role required ('Admin' | 'Owner').
 */
export async function checkUserPermission(userId: string, requiredRole: 'Owner' | 'Admin' | 'Member'): Promise<void> {
    if (!userId || !z.string().uuid().safeParse(userId).success) {
        throw new Error('Invalid user ID provided');
    }
    
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('check_user_permission', { 
        p_user_id: userId, 
        p_required_role: requiredRole as any
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
                updated_at: new Date().toISOString(),
                alert_settings: settings.alert_settings as any // Type assertion for JSON compatibility
            })
            .eq('company_id', companyId)
            .select()
            .single();
            
        if (error) {
            logError(error, { context: 'updateSettingsInDb failed', companyId });
            return { success: false, error: "Unable to save settings. Please try again." };
        }
        
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
            const searchTerm = validatedParams.query.trim();
            // Try full text search first, fall back to ilike search if fts column doesn't exist
            try {
                const ftsSearchTerm = searchTerm.replace(/ /g, ' & ');
                query = query.textSearch('fts', `'${ftsSearchTerm}'`, {type: 'websearch', config: 'english'});
            } catch (ftsError) {
                // Fallback to regular text search on multiple columns
                query = query.or(`product_title.ilike.%${searchTerm}%,product_type.ilike.%${searchTerm}%,product_status.ilike.%${searchTerm}%`);
            }
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
            // If it's the fts column error, retry with fallback search
            if (error.message?.includes('fts does not exist')) {
                let fallbackQuery = supabase
                    .from('product_variants_with_details')
                    .select('*', { count: 'exact' })
                    .eq('company_id', companyId);

                if (validatedParams.query) {
                    const searchTerm = validatedParams.query.trim();
                    fallbackQuery = fallbackQuery.or(`product_title.ilike.%${searchTerm}%,product_type.ilike.%${searchTerm}%,product_status.ilike.%${searchTerm}%`);
                }
                
                if (validatedParams.status && validatedParams.status !== 'all') {
                    fallbackQuery = fallbackQuery.eq('product_status', validatedParams.status);
                }
                
                const { data: fallbackData, error: fallbackError, count: fallbackCount } = await fallbackQuery
                    .order(sortBy, { ascending: sortDirection === 'asc' })
                    .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
                
                if (fallbackError) {
                    logError(fallbackError, { context: 'getUnifiedInventoryFromDB fallback query failed', companyId });
                    throw new Error('Failed to retrieve inventory data');
                }
                
                return {
                    items: z.array(UnifiedInventoryItemSchema).parse(fallbackData || []),
                    totalCount: fallbackCount || 0,
                };
            }
            
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
            throw new Error('Unable to create supplier. Please check fields and try again.');
        }
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
        throw new Error('Unable to save supplier. Please check all fields and try again.');
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
        throw new Error('Could not delete supplier. It may be associated with existing purchase orders.');
    }
}

export async function getCustomersFromDB(companyId: string, params: { query?: string, offset: number, limit: number }) {
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    let query = supabase.from('customers_view').select('*', {count: 'exact'}).eq('company_id', companyId);
    
    if(validatedParams.query) {
        query = query.or(`customer_name.ilike.%${validatedParams.query}%,email.ilike.%${validatedParams.query}%`);
    }
    
    const limit = Math.min(validatedParams.limit || 25, 5000);
    const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
    
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
    // Note: Using customer_analytics as sales_analytics function doesn't exist in database types
    const { data, error } = await supabase.rpc('get_customer_analytics', { p_company_id: companyId });
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
    return CustomerAnalyticsSchema.parse(data || {});
}

export async function getDeadStockReportFromDB(companyId: string): Promise<{ deadStockItems: z.infer<typeof DeadStockItemSchema>[], totalValue: number, totalUnits: number }> {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_dead_stock_report', { p_company_id: companyId });

    if (error) {
        logError(error, { context: 'getDeadStockReportFromDB failed' });
        return { deadStockItems: [], totalValue: 0, totalUnits: 0 };
    }
    
    const reportData = (data as any) || { dead_stock_items: [], total_value: 0 };

    const deadStockItems = DeadStockItemSchema.array().parse(reportData.dead_stock_items || []);
    const totalValue = reportData.total_value || 0;
    const totalUnits = deadStockItems.reduce((sum: number, item) => sum + item.quantity, 0);

    return { deadStockItems, totalValue, totalUnits };
}

export async function getReorderSuggestionsFromDB(companyId: string): Promise<ReorderSuggestion[]> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid Company ID');
    }
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_reorder_suggestions', { p_company_id: companyId });
        
        if (error) {
            throw error;
        }

        const suggestions = z.array(ReorderSuggestionSchema.omit({
            base_quantity: true,
            adjustment_reason: true,
            seasonality_factor: true,
            confidence: true,
        })).parse(data || []);

        return suggestions.map(s => {
            if (s.suggested_reorder_quantity > 10000) {
                s.suggested_reorder_quantity = 10000;
            }
            return {
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: null,
                seasonality_factor: 1.0,
                confidence: 0.5,
            };
        });

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
    return z.array(SupplierPerformanceReportSchema).parse(data || []);
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
    
    // Calculate total cost from line items
    const totalCost = poData.line_items?.reduce((sum, item) => sum + (item.quantity * item.cost), 0) || 0;
    
    // Generate PO number (simple increment - in production this should be more sophisticated)
    const poNumber = `PO-${Date.now()}`;
    
    // Insert purchase order directly since create_full_purchase_order function doesn't exist
    const { data: poInsert, error: poError } = await supabase
        .from('purchase_orders')
        .insert({
            company_id: companyId,
            supplier_id: poData.supplier_id,
            status: poData.status,
            notes: poData.notes || '',
            expected_arrival_date: poData.expected_arrival_date?.toISOString() || null,
            total_cost: totalCost,
            po_number: poNumber,
        })
        .select('id')
        .single();

    if (poError) {
        logError(poError, { context: 'Failed to insert purchase order' });
        throw new Error('Database error while creating purchase order.');
    }

    // Insert line items if they exist
    if (poData.line_items && poData.line_items.length > 0) {
        const lineItemsData = poData.line_items.map(item => ({
            purchase_order_id: poInsert.id,
            company_id: companyId,
            variant_id: item.variant_id,
            quantity: item.quantity,
            cost: item.cost,
        }));

        const { error: lineItemsError } = await supabase
            .from('purchase_order_line_items')
            .insert(lineItemsData);

        if (lineItemsError) {
            logError(lineItemsError, { context: 'Failed to insert purchase order line items' });
            // Try to clean up the purchase order
            await supabase.from('purchase_orders').delete().eq('id', poInsert.id);
            throw new Error('Database error while creating purchase order line items.');
        }
    }
    
    return poInsert.id;
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
        p_notes: poData.notes || '',
        p_expected_arrival: poData.expected_arrival_date?.toISOString() || '',
        p_line_items: poData.line_items as unknown as Json,
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
    
    // Transform the data to match the expected schema
    const transformedData = (data || []).map(item => ({
        ...item,
        id: item.id || '',
        company_id: item.company_id || '',
        status: item.status || '',
        po_number: item.po_number || '',
        total_cost: item.total_cost || 0,
        created_at: item.created_at || new Date().toISOString(),
        updated_at: null,
        supplier_id: null,
        line_items: Array.isArray(item.line_items) ? item.line_items as any[] : null
    }));
    
    return transformedData as PurchaseOrderWithItemsAndSupplier[];
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
    
    // Transform the data to match the expected schema
    const transformedData = {
        ...data,
        id: data.id || '',
        company_id: data.company_id || '',
        status: data.status || '',
        po_number: data.po_number || '',
        total_cost: data.total_cost || 0,
        created_at: data.created_at || new Date().toISOString(),
        updated_at: null,
        supplier_id: null,
        line_items: Array.isArray(data.line_items) ? data.line_items as any[] : null
    };
    
    return transformedData as PurchaseOrderWithItemsAndSupplier;
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
        throw error;
    }
    return data; 
}
export async function getSalesVelocityFromDB(companyId: string, days: number = 30, limit: number = 100) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    try {
        // Get recent sales data with dates for proper velocity calculation
        const { data, error } = await supabase
            .from('order_line_items')
            .select(`
                sku,
                product_name,
                quantity,
                price,
                created_at
            `)
            .eq('company_id', companyId)
            .gte('created_at', new Date(Date.now() - (days * 24 * 60 * 60 * 1000)).toISOString())
            .order('created_at', { ascending: false });

        if (error) {
            logError(error, { context: 'getSalesVelocityFromDB failed' });
            return null;
        }

        if (!data || data.length === 0) {
            return [];
        }

        // Advanced velocity analysis with trend detection
        const velocityMap = new Map();
        const currentDate = new Date();
        
        data.forEach((item: any) => {
            const sku = item.sku;
            const saleDate = new Date(item.created_at);
            const daysAgo = Math.floor((currentDate.getTime() - saleDate.getTime()) / (1000 * 60 * 60 * 24));
            
            if (!velocityMap.has(sku)) {
                velocityMap.set(sku, {
                    sku,
                    product_name: item.product_name,
                    total_quantity: 0,
                    total_revenue: 0,
                    sales_by_week: new Array(Math.ceil(days / 7)).fill(0),
                    last_sale_days_ago: daysAgo,
                    sales_frequency: 0
                });
            }
            
            const product = velocityMap.get(sku);
            product.total_quantity += item.quantity;
            product.total_revenue += item.quantity * item.price;
            product.last_sale_days_ago = Math.min(product.last_sale_days_ago, daysAgo);
            product.sales_frequency += 1;
            
            // Track weekly sales for trend analysis
            const weekIndex = Math.floor(daysAgo / 7);
            if (weekIndex < product.sales_by_week.length) {
                product.sales_by_week[weekIndex] += item.quantity;
            }
        });

        // Calculate velocity metrics and trends
        const results = Array.from(velocityMap.values()).map((product: any) => {
            const dailyVelocity = product.total_quantity / days;
            const weeklyVelocity = dailyVelocity * 7;
            const monthlyVelocity = dailyVelocity * 30;
            
            // Calculate trend from weekly data (recent weeks vs older weeks)
            const recentWeeks = product.sales_by_week.slice(0, 2); // Last 2 weeks
            const olderWeeks = product.sales_by_week.slice(2, 4); // 2 weeks before that
            
            const recentAvg = recentWeeks.reduce((a: number, b: number) => a + b, 0) / Math.max(1, recentWeeks.length);
            const olderAvg = olderWeeks.reduce((a: number, b: number) => a + b, 0) / Math.max(1, olderWeeks.length);
            
            let trend = 'stable';
            let trend_percentage = 0;
            
            if (olderAvg > 0) {
                trend_percentage = Math.round(((recentAvg - olderAvg) / olderAvg) * 100);
                if (trend_percentage > 20) trend = 'increasing';
                else if (trend_percentage < -20) trend = 'decreasing';
            } else if (recentAvg > 0) {
                trend = 'increasing';
                trend_percentage = 100;
            }
            
            // Velocity classification
            let velocity_category = 'slow';
            if (weeklyVelocity >= 10) velocity_category = 'fast';
            else if (weeklyVelocity >= 3) velocity_category = 'medium';
            
            // Generate actionable insights
            let insight = 'Monitor performance';
            if (velocity_category === 'fast' && trend === 'increasing') {
                insight = 'High performer - ensure adequate stock levels';
            } else if (velocity_category === 'fast' && trend === 'decreasing') {
                insight = 'Slowing down - investigate causes or consider promotions';
            } else if (velocity_category === 'slow' && trend === 'increasing') {
                insight = 'Gaining momentum - consider increasing marketing';
            } else if (velocity_category === 'slow' && product.last_sale_days_ago > 14) {
                insight = 'Stagnant - review pricing or consider markdown';
            } else if (velocity_category === 'medium') {
                insight = 'Steady performer - maintain current strategy';
            }
            
            // Sales consistency score (0-1, higher = more consistent)
            const weeklyVariance = product.sales_by_week.reduce((acc: number, week: number) => {
                return acc + Math.pow(week - (product.total_quantity / product.sales_by_week.length), 2);
            }, 0) / product.sales_by_week.length;
            
            const consistency_score = Math.max(0, Math.min(1, 1 - (Math.sqrt(weeklyVariance) / (product.total_quantity / product.sales_by_week.length + 1))));
            
            return {
                sku: product.sku,
                product_name: product.product_name,
                daily_velocity: Math.round(dailyVelocity * 100) / 100,
                weekly_velocity: Math.round(weeklyVelocity * 100) / 100,
                monthly_velocity: Math.round(monthlyVelocity * 100) / 100,
                velocity_category,
                trend,
                trend_percentage,
                total_revenue: product.total_revenue,
                sales_frequency: product.sales_frequency,
                last_sale_days_ago: product.last_sale_days_ago,
                consistency_score: Math.round(consistency_score * 100) / 100,
                insight,
                velocity_score: Math.round((weeklyVelocity * 10 + (trend_percentage > 0 ? trend_percentage : 0) + consistency_score * 20) * 100) / 100
            };
        })
        .filter((item: any) => item.total_revenue > 0) // Only include products with sales
        .sort((a, b) => b.velocity_score - a.velocity_score) // Sort by overall velocity score
        .slice(0, limit);

        return results;
        
    } catch (error) {
        logError(error, { context: 'getSalesVelocityFromDB unexpected error' });
        return [];
    }
}

export async function getDemandForecastFromDB(companyId: string, days: number = 90) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    try {
        // Get historical sales data with proper date filtering for better forecasting
        const { data, error } = await supabase
            .from('order_line_items')
            .select(`
                sku,
                product_name,
                quantity,
                price,
                created_at
            `)
            .eq('company_id', companyId)
            .gte('created_at', new Date(Date.now() - (days * 24 * 60 * 60 * 1000)).toISOString());

        if (error) {
            logError(error, { context: 'getDemandForecastFromDB failed' });
            return null;
        }

        if (!data || data.length === 0) {
            return [];
        }

        // Advanced forecasting with trend analysis
        const forecastMap = new Map();
        const currentDate = new Date();
        
        data.forEach((item: any) => {
            const sku = item.sku;
            const saleDate = new Date(item.created_at);
            const daysAgo = Math.floor((currentDate.getTime() - saleDate.getTime()) / (1000 * 60 * 60 * 24));
            
            if (!forecastMap.has(sku)) {
                forecastMap.set(sku, {
                    sku,
                    product_name: item.product_name,
                    sales_history: [],
                    total_quantity: 0,
                    total_revenue: 0
                });
            }
            
            const product = forecastMap.get(sku);
            product.sales_history.push({
                quantity: item.quantity,
                revenue: item.quantity * item.price,
                days_ago: daysAgo
            });
            product.total_quantity += item.quantity;
            product.total_revenue += item.quantity * item.price;
        });

        const result = Array.from(forecastMap.values()).map((product: any) => {
            // Calculate trend using linear regression on recent vs older sales
            const recentSales = product.sales_history.filter((s: any) => s.days_ago <= 30);
            const olderSales = product.sales_history.filter((s: any) => s.days_ago > 30);
            
            const recentAvg = recentSales.length > 0 ? 
                recentSales.reduce((sum: number, s: any) => sum + s.quantity, 0) / recentSales.length : 0;
            const olderAvg = olderSales.length > 0 ? 
                olderSales.reduce((sum: number, s: any) => sum + s.quantity, 0) / olderSales.length : recentAvg;
            
            // Calculate 30-day forecast with trend adjustment
            const baseDemand = product.total_quantity / (days / 30); // Average monthly demand
            const trendMultiplier = recentAvg > olderAvg ? 1.2 : recentAvg < olderAvg * 0.8 ? 0.8 : 1.0;
            const forecastedDemand = Math.round(baseDemand * trendMultiplier);
            
            // Calculate confidence based on data consistency
            const variance = product.sales_history.reduce((acc: number, sale: any) => {
                const expectedDaily = product.total_quantity / days;
                return acc + Math.pow(sale.quantity - expectedDaily, 2);
            }, 0) / product.sales_history.length;
            
            const confidence = Math.max(0.2, Math.min(0.95, 1 - (Math.sqrt(variance) / (product.total_quantity / days + 1))));
            
            let trend = 'stable';
            if (recentAvg > olderAvg * 1.1) trend = 'increasing';
            else if (recentAvg < olderAvg * 0.9) trend = 'decreasing';
            
            // Add business intelligence insights
            let insight = 'Normal demand pattern';
            if (forecastedDemand > baseDemand * 1.5) {
                insight = 'High growth expected - consider increasing stock';
            } else if (forecastedDemand < baseDemand * 0.5) {
                insight = 'Declining demand - review inventory levels';
            } else if (confidence < 0.4) {
                insight = 'Irregular sales pattern - monitor closely';
            }
            
            return {
                sku: product.sku,
                product_name: product.product_name,
                forecasted_demand: Math.max(0, forecastedDemand),
                confidence: Math.round(confidence * 100) / 100,
                trend,
                insight,
                historical_avg: Math.round(baseDemand * 100) / 100,
                recent_performance: Math.round(recentAvg * 30 * 100) / 100, // Monthly recent performance
                total_revenue: product.total_revenue,
                priority: forecastedDemand > baseDemand * 1.2 ? 'high' : 
                         forecastedDemand < baseDemand * 0.6 ? 'low' : 'medium'
            };
        })
        .filter((item: any) => item.forecasted_demand > 0 || item.total_revenue > 100) // Include revenue products even with low forecast
        .sort((a, b) => b.forecasted_demand - a.forecasted_demand);

        return result;
        
    } catch (error) {
        logError(error, { context: 'getDemandForecastFromDB unexpected error' });
        return [];
    }
}

interface AbcAnalysisItem {
  id: string;
  name: string;
  sku: string;
  category: 'A' | 'B' | 'C';
  revenue: number;
  margin: number;
  velocity: number;
  composite_score: number;
  performance_indicator: string;
  risk_factor: string;
  recommendation: string;
}

interface ProductMetric {
  sku: string;
  product_name: string;
  revenue: number;
  margin: number;
  margin_percentage: number;
  velocity: number;
  revenue_percentile: number;
  margin_percentile: number;
  velocity_percentile: number;
  turnover_ratio: number;
  last_order_days: number;
}

export async function getAbcAnalysisFromDB(companyId: string): Promise<AbcAnalysisItem[] | null> { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    try {
        // Get comprehensive product data with enhanced metrics
        const { data: orderData, error: orderError } = await supabase
            .from('order_line_items')
            .select(`
                sku,
                product_name,
                quantity,
                price,
                created_at
            `)
            .eq('company_id', companyId)
            .gte('created_at', new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString());

        if (orderError) {
            logError(orderError, { context: 'getAbcAnalysisFromDB order data failed' });
            return null;
        }

        // Get inventory data for current stock levels and costs
        const { data: inventoryData, error: inventoryError } = await supabase
            .from('product_variants')
            .select(`
                sku,
                title,
                current_quantity,
                cost,
                price,
                updated_at
            `)
            .eq('company_id', companyId);

        if (inventoryError) {
            logError(inventoryError, { context: 'getAbcAnalysisFromDB inventory data failed' });
        }

        if (!orderData || orderData.length === 0) {
            return [];
        }

        // Enhanced Multi-Dimensional ABC Analysis
        const productMetrics = new Map();

        // Create inventory lookup map
        const inventoryMap = new Map();
        (inventoryData || []).forEach((item: any) => {
            inventoryMap.set(item.sku, item);
        });

        // Calculate enhanced metrics per SKU
        orderData.forEach((item: any) => {
            const sku = item.sku;
            const revenue = item.quantity * item.price;
            const inventoryItem = inventoryMap.get(sku);
            const cost = inventoryItem?.cost || 0;
            const margin = revenue - (item.quantity * cost);
            const orderDate = new Date(item.created_at);
            const daysAgo = Math.floor((Date.now() - orderDate.getTime()) / (24 * 60 * 60 * 1000));

            if (!productMetrics.has(sku)) {
                productMetrics.set(sku, {
                    sku,
                    product_name: item.product_name,
                    revenue: 0,
                    margin: 0,
                    quantity_sold: 0,
                    order_frequency: 0,
                    last_order_days: daysAgo,
                    orders: [],
                    current_stock: inventoryItem?.current_quantity || 0,
                    unit_cost: cost,
                    unit_price: inventoryItem?.price || item.price
                });
            }

            const existing = productMetrics.get(sku);
            existing.revenue += revenue;
            existing.margin += margin;
            existing.quantity_sold += item.quantity;
            existing.orders.push({
                date: orderDate,
                quantity: item.quantity,
                revenue: revenue
            });
            existing.last_order_days = Math.min(existing.last_order_days, daysAgo);
        });

        // Calculate velocity and frequency metrics
        productMetrics.forEach((product) => {
            // Calculate order frequency (orders per month)
            const uniqueOrderDates = new Set(
                product.orders.map((order: any) => 
                    order.date.toISOString().substring(0, 7) // YYYY-MM
                )
            );
            product.order_frequency = uniqueOrderDates.size / 3; // 3 months = 90 days

            // Calculate sales velocity (units per day)
            product.velocity = product.quantity_sold / 90;

            // Calculate margin percentage
            product.margin_percentage = product.revenue > 0 ? (product.margin / product.revenue) * 100 : 0;

            // Calculate turnover ratio
            product.turnover_ratio = product.current_stock > 0 ? product.quantity_sold / product.current_stock : 0;

            // Calculate recency score (lower is better for recent orders)
            product.recency_score = Math.min(product.last_order_days / 30, 3); // Max 3 months
        });

        // Sort and create comprehensive rankings
        const products = Array.from(productMetrics.values());

        // Revenue ranking
        const revenueRanked = [...products].sort((a, b) => b.revenue - a.revenue);
        revenueRanked.forEach((product, index) => {
            product.revenue_rank = index + 1;
            product.revenue_percentile = ((products.length - index) / products.length) * 100;
        });

        // Margin ranking
        const marginRanked = [...products].sort((a, b) => b.margin - a.margin);
        marginRanked.forEach((product, index) => {
            product.margin_rank = index + 1;
            product.margin_percentile = ((products.length - index) / products.length) * 100;
        });

        // Velocity ranking
        const velocityRanked = [...products].sort((a, b) => b.velocity - a.velocity);
        velocityRanked.forEach((product, index) => {
            product.velocity_rank = index + 1;
            product.velocity_percentile = ((products.length - index) / products.length) * 100;
        });

        // Enhanced ABC Categorization with Multiple Dimensions
        const result: AbcAnalysisItem[] = products.map((product: ProductMetric) => {
            // Multi-dimensional scoring (weighted)
            const revenueWeight = 0.4;
            const marginWeight = 0.3;
            const velocityWeight = 0.3;

            const compositeScore = 
                (product.revenue_percentile * revenueWeight) +
                (product.margin_percentile * marginWeight) +
                (product.velocity_percentile * velocityWeight);

            // Enhanced categorization with dynamic thresholds
            let category: 'A' | 'B' | 'C' = 'C';
            let recommendation = '';

            if (compositeScore >= 80) {
                category = 'A';
                recommendation = 'Maintain high stock levels, optimize pricing, ensure supplier reliability';
            } else if (compositeScore >= 60) {
                category = 'B';
                recommendation = 'Monitor closely, balance inventory investment, review periodically';
            } else {
                category = 'C';
                recommendation = 'Minimize inventory, consider discontinuation if consistently low';
            }

            // Special case adjustments
            if (product.margin_percentage < 10 && category === 'A') {
                recommendation += ' - ⚠️ Low margin product, review pricing strategy';
            }
            if (product.velocity < 0.1 && category !== 'C') {
                recommendation += ' - ⚠️ Slow moving, consider promotional activities';
            }
            if (product.turnover_ratio > 10) {
                recommendation += ' - 🔥 High turnover, consider increasing stock levels';
            }

            return {
                id: String(product.sku || ''), // Using SKU as ID, ensure string type
                name: String(product.product_name || ''),
                sku: String(product.sku || ''),
                category,
                revenue: Number(product.revenue) || 0,
                margin: Number(product.margin) || 0,
                velocity: Math.round(product.velocity * 100) / 100,
                composite_score: Math.round(compositeScore * 10) / 10,
                performance_indicator: product.margin_percentage > 20 ? 'excellent' : 
                                     product.margin_percentage > 10 ? 'good' : 'poor',
                risk_factor: product.margin_percentage < 10 ? 'Low Margin' :
                           product.velocity < 0.1 ? 'Slow Moving' :
                           product.last_order_days > 60 ? 'Stale Inventory' : 'Normal',
                recommendation
            };
        }).sort((a, b) => b.composite_score - a.composite_score);

        return result;

    } catch (error) {
        logError(error, { context: 'getAbcAnalysisFromDB comprehensive analysis failed' });
        return null;
    }
}

export async function getGrossMarginAnalysisFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    // Get cost and price data for margin analysis without complex joins
    const { data, error } = await supabase
        .from('order_line_items')
        .select(`
            sku,
            product_name,
            quantity,
            price,
            cost_at_time
        `)
        .eq('company_id', companyId);

    if (error) {
        logError(error, { context: 'getGrossMarginAnalysisFromDB failed' });
        return null; // Return null instead of throwing to prevent crashes
    }

    if (!data || data.length === 0) {
        return [];
    }

    // Calculate margins per SKU
    const marginMap = new Map();
    
    data.forEach((item: any) => {
        const sku = item.sku;
        const revenue = item.quantity * item.price;
        const cost = item.quantity * (item.cost_at_time || 0);
        const margin = revenue - cost;
        
        if (!marginMap.has(sku)) {
            marginMap.set(sku, {
                sku,
                product_name: item.product_name,
                total_revenue: 0,
                total_cost: 0,
                total_margin: 0,
                quantity_sold: 0
            });
        }
        
        const existing = marginMap.get(sku);
        existing.total_revenue += revenue;
        existing.total_cost += cost;
        existing.total_margin += margin;
        existing.quantity_sold += item.quantity;
    });

    const result = Array.from(marginMap.values()).map((item: any) => ({
        sku: item.sku,
        product_name: item.product_name,
        gross_margin_percentage: item.total_revenue > 0 ? ((item.total_margin / item.total_revenue) * 100) : 0,
        revenue: item.total_revenue,
        cost: item.total_cost,
        profit: item.total_margin,
        quantity_sold: item.quantity_sold,
        margin_per_unit: item.quantity_sold > 0 ? (item.total_margin / item.quantity_sold) : 0
    })).filter((item: any) => item.revenue > 0)
      .sort((a, b) => b.gross_margin_percentage - a.gross_margin_percentage);

    return result;
}
export async function getMarginTrendsFromDB(companyId: string) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_margin_trends', { p_company_id: companyId });
    if(error) {
        logError(error, { context: 'getMarginTrendsFromDB failed' });
        throw error;
    }
    return data; 
}
export async function getFinancialImpactOfPromotionFromDB(companyId: string, skus: string[], discount: number, duration: number) { 
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_financial_impact_of_promotion', { p_company_id: companyId, p_skus: skus, p_discount_percentage: discount, p_duration_days: duration });
    if(error) {
        logError(error, { context: 'getFinancialImpactOfPromotionFromDB failed' });
        throw error;
    }
    return data; 
}

export async function createPurchaseOrdersFromSuggestionsInDb(companyId: string, userId: string, suggestions: ReorderSuggestion[]) {
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

export async function getHistoricalSalesForSkus(
    companyId: string, 
    skus: string[]
): Promise<any[]> {
    const supabase = getServiceRoleClient();
    
    const { data, error } = await supabase.rpc('get_historical_sales_for_skus', { p_company_id: companyId, p_skus: skus});
        
    if (error) throw error;
    
    return Array.isArray(data) ? data : [];
}

export async function getHistoricalSalesForSingleSkuFromDB(
    companyId: string, 
    sku: string
): Promise<{ sale_date: string; total_quantity: number }[]> {
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

export async function getDashboardMetrics(companyId: string, period: string): Promise<DashboardMetrics> {
    if (!z.string().uuid().safeParse(companyId).success) {
        throw new Error('Invalid company ID format');
    }
    
    const days = parseInt(String(period).replace(/\D/g, ''), 10) || 30;
    
    try {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_dashboard_metrics', { 
            p_company_id: companyId, 
            p_days: days 
        });
        
        if (error) {
            logError(error, { context: 'get_dashboard_metrics failed', companyId, period });
            throw new Error('Could not retrieve dashboard metrics from the database.');
        }
        
        if (data == null) {
            logger.warn('[RPC Error] get_dashboard_metrics returned null. This can happen with no data.');
            // Return a default, valid object that conforms to the schema
            return {
                total_revenue: 0,
                revenue_change: 0,
                total_orders: 0,
                orders_change: 0,
                new_customers: 0,
                customers_change: 0,
                dead_stock_value: 0,
                sales_over_time: [],
                top_products: [],
                inventory_summary: {
                    total_value: 0,
                    in_stock_value: 0,
                    low_stock_value: 0,
                    dead_stock_value: 0,
                },
            };
        }
        
        // Handle case where RPC returns array instead of object
        const metricsData = Array.isArray(data) && data.length > 0 ? data[0] : data;
        
        if (!metricsData || typeof metricsData !== 'object') {
            logger.warn('[RPC Error] get_dashboard_metrics returned invalid data format.');
            return {
                total_revenue: 0,
                revenue_change: 0,
                total_orders: 0,
                orders_change: 0,
                new_customers: 0,
                customers_change: 0,
                dead_stock_value: 0,
                sales_over_time: [],
                top_products: [],
                inventory_summary: {
                    total_value: 0,
                    in_stock_value: 0,
                    low_stock_value: 0,
                    dead_stock_value: 0,
                },
            };
        }
        
        // Ensure the data from the RPC conforms to the Zod schema before returning
        return DashboardMetricsSchema.parse(metricsData);
    } catch (e) {
        logError(e, { context: 'getDashboardMetrics failed', companyId, period });
        throw new Error('Could not retrieve dashboard metrics from the database.');
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
        
        return InventoryAnalyticsSchema.parse(data || {
            total_inventory_value: 0,
            total_products: 0,
            total_variants: 0,
            low_stock_items: 0
        });
    } catch (error) {
        logError(error, { context: 'getInventoryAnalyticsFromDB unexpected error', companyId });
        throw error;
    }
}

export async function refreshMaterializedViews(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) {
        logger.warn(`Invalid companyId passed to refreshMaterializedViews: ${companyId}`);
        return;
    }
    logger.info(`Materialized view refresh triggered for company ${companyId}`);
    try {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('refresh_all_matviews', { p_company_id: companyId });
        if(error) {
            logError(error, { context: 'refresh_all_matviews RPC failed', companyId });
        } else {
            logger.info(`Successfully refreshed materialized views for company ${companyId}`);
        }
    } catch (e) {
        logError(e, { context: 'refreshMaterializedViews unexpected error', companyId });
    }
}

export async function getAuditLogFromDB(companyId: string, params: { query?: string; offset: number, limit: number }): Promise<{ items: AuditLogEntry[], totalCount: number }> {
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    let query = supabase.from('audit_log_view').select('*', {count: 'exact'}).eq('company_id', companyId);
    
    if(validatedParams.query) {
        query = query.or(`action.ilike.%${validatedParams.query}%,user_email.ilike.%${validatedParams.query}%`);
    }
    
    const limit = Math.min(validatedParams.limit || 25, 100);
    const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
    
    if(error) throw error;
    return {items: AuditLogEntrySchema.array().parse(data || []), totalCount: count || 0};
}

export async function getFeedbackFromDB(companyId: string, params: { query?: string; offset: number, limit: number }): Promise<{ items: FeedbackWithMessages[], totalCount: number }> {
    const validatedParams = DatabaseQueryParamsSchema.parse(params);
    const supabase = getServiceRoleClient();
    
    let query = supabase.from('feedback_view').select('*', {count: 'exact'}).eq('company_id', companyId);
    
    if(validatedParams.query) {
        query = query.or(`user_email.ilike.%${validatedParams.query}%,user_message_content.ilike.%${validatedParams.query}%`);
    }
    
    const limit = Math.min(validatedParams.limit || 25, 100);
    const { data, error, count } = await query
        .order('created_at', { ascending: false })
        .range(validatedParams.offset || 0, (validatedParams.offset || 0) + limit - 1);
    
    if(error) throw error;
    return {items: FeedbackSchema.array().parse(data || []), totalCount: count || 0};
}

// Advanced Analytics Functions
export async function getHiddenRevenueOpportunitiesFromDB(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    
    try {
        // Get comprehensive analytics data in parallel for AI analysis
        const [marginData, velocityData, demandData, abcData, turnoverData] = await Promise.all([
            getGrossMarginAnalysisFromDB(companyId),
            getSalesVelocityFromDB(companyId, 90, 200),
            getDemandForecastFromDB(companyId, 90),
            getAbcAnalysisFromDB(companyId),
            getInventoryTurnoverAnalysisFromDB(companyId, 365)
        ]);
        
        // Handle null cases
        if (!marginData || !velocityData || !demandData) {
            return [];
        }
        
        // AI-powered opportunity discovery algorithm
        const opportunities: any[] = [];
        const processedSkus = new Set();
        
        // 1. HIGH-MARGIN UNDERPERFORMERS - Products with excellent margins but poor sales
        marginData
            .filter((item: any) => item.gross_margin_percentage > 45 && item.revenue > 100)
            .forEach((marginItem: any) => {
                const velocityItem = velocityData.find((v: any) => v.sku === marginItem.sku);
                const velocity = velocityItem ? velocityItem.daily_velocity : 0;
                const demandItem = demandData.find((d: any) => d.sku === marginItem.sku);
                
                if (velocity < 0.8 && !processedSkus.has(marginItem.sku)) {
                    processedSkus.add(marginItem.sku);
                    
                    const potentialDaily = Math.max(2.0, velocity * 3); // Conservative 3x velocity target
                    const currentMonthly = velocity * 30;
                    const targetMonthly = potentialDaily * 30;
                    const monthlyRevenueLift = (targetMonthly - currentMonthly) * (marginItem.revenue / marginItem.quantity_sold);
                    const annualRevenuePotential = monthlyRevenueLift * 12;
                    
                    opportunities.push({
                        sku: marginItem.sku,
                        product_name: marginItem.product_name,
                        opportunity_type: 'High-Margin Underperformer',
                        priority: 'Critical',
                        current_performance: {
                            daily_velocity: velocity,
                            margin_percentage: marginItem.gross_margin_percentage,
                            monthly_revenue: currentMonthly * (marginItem.revenue / marginItem.quantity_sold),
                            revenue_rank: 'Bottom 50%'
                        },
                        opportunity_metrics: {
                            potential_daily_velocity: potentialDaily,
                            target_margin: marginItem.gross_margin_percentage,
                            monthly_revenue_lift: monthlyRevenueLift,
                            annual_revenue_potential: annualRevenuePotential,
                            confidence_score: demandItem ? Math.min(0.85, demandItem.confidence + 0.2) : 0.65
                        },
                        ai_insights: {
                            primary_issue: velocity < 0.2 ? 'Visibility & Discovery Problem' : 'Market Positioning Issue',
                            demand_signal: demandItem ? 
                                demandItem.trend === 'increasing' ? 'Growing demand detected' : 
                                demandItem.forecasted_demand > 5 ? 'Stable demand exists' : 'Limited demand signal'
                                : 'Demand analysis needed',
                            competitive_advantage: `Excellent ${marginItem.gross_margin_percentage.toFixed(1)}% margin provides pricing flexibility`,
                            market_opportunity: velocity < 0.2 ? 'Untapped market potential' : 'Optimization opportunity'
                        },
                        recommended_actions: [
                            {
                                action: velocity < 0.2 ? 'Launch visibility campaign' : 'Optimize product positioning',
                                impact: 'High',
                                timeline: '2-4 weeks',
                                investment: velocity < 0.2 ? 'Medium marketing spend' : 'Low - positioning only',
                                expected_lift: '150-300%'
                            },
                            {
                                action: 'A/B test pricing strategy',
                                impact: 'Medium',
                                timeline: '1-2 weeks',
                                investment: 'Low - testing only',
                                expected_lift: '20-50%'
                            },
                            {
                                action: 'Cross-sell with high-velocity products',
                                impact: 'Medium',
                                timeline: '1 week',
                                investment: 'Low - bundling strategy',
                                expected_lift: '30-60%'
                            }
                        ],
                        financial_impact: {
                            investment_needed: velocity < 0.2 ? 500 : 200,
                            roi_estimate: velocity < 0.2 ? 8.5 : 6.2,
                            payback_period_months: 2.5,
                            risk_level: 'Low'
                        },
                        opportunity_score: (marginItem.gross_margin_percentage * 2) + (annualRevenuePotential / 100) + (velocity < 0.2 ? 50 : 30)
                    });
                }
            });
        
        // 2. TREND ACCELERATORS - Products with positive demand trends but low current performance
        demandData
            .filter((item: any) => item.trend === 'increasing' && item.confidence > 0.6 && item.forecasted_demand > 0)
            .forEach((demandItem: any) => {
                if (!processedSkus.has(demandItem.sku)) {
                    const velocityItem = velocityData.find((v: any) => v.sku === demandItem.sku);
                    const marginItem = marginData.find((m: any) => m.sku === demandItem.sku);
                    
                    if (velocityItem && marginItem && marginItem.gross_margin_percentage > 25) {
                        processedSkus.add(demandItem.sku);
                        
                        const currentVelocity = velocityItem.daily_velocity;
                        const trendMultiplier = demandItem.confidence > 0.8 ? 2.5 : 2.0;
                        const targetVelocity = Math.min(currentVelocity * trendMultiplier, 15); // Cap at 15 units/day
                        const monthlyLift = (targetVelocity - currentVelocity) * 30 * (marginItem.revenue / marginItem.quantity_sold);
                        const annualPotential = monthlyLift * 12;
                        
                        opportunities.push({
                            sku: demandItem.sku,
                            product_name: demandItem.product_name,
                            opportunity_type: 'Trend Accelerator',
                            priority: demandItem.confidence > 0.8 ? 'High' : 'Medium',
                            current_performance: {
                                daily_velocity: currentVelocity,
                                margin_percentage: marginItem.gross_margin_percentage,
                                monthly_revenue: currentVelocity * 30 * (marginItem.revenue / marginItem.quantity_sold),
                                trend_direction: 'Increasing'
                            },
                            opportunity_metrics: {
                                potential_daily_velocity: targetVelocity,
                                trend_confidence: demandItem.confidence,
                                monthly_revenue_lift: monthlyLift,
                                annual_revenue_potential: annualPotential,
                                confidence_score: demandItem.confidence
                            },
                            ai_insights: {
                                primary_opportunity: 'Rising demand trend detected by AI forecasting',
                                demand_signal: `${demandItem.trend_percentage > 0 ? '+' : ''}${demandItem.trend_percentage}% trend momentum`,
                                timing_advantage: 'Early trend detection - competitive advantage available',
                                market_dynamics: demandItem.insight || 'Positive market momentum'
                            },
                            recommended_actions: [
                                {
                                    action: 'Scale inventory to meet growing demand',
                                    impact: 'High',
                                    timeline: '1-2 weeks',
                                    investment: 'Medium - inventory investment',
                                    expected_lift: '100-200%'
                                },
                                {
                                    action: 'Amplify marketing during trend peak',
                                    impact: 'High',
                                    timeline: '1 week',
                                    investment: 'Medium - marketing spend',
                                    expected_lift: '80-150%'
                                },
                                {
                                    action: 'Optimize pricing for demand curve',
                                    impact: 'Medium',
                                    timeline: '3-5 days',
                                    investment: 'Low - pricing strategy',
                                    expected_lift: '15-35%'
                                }
                            ],
                            financial_impact: {
                                investment_needed: 800,
                                roi_estimate: 7.8,
                                payback_period_months: 1.8,
                                risk_level: 'Medium'
                            },
                            opportunity_score: (demandItem.confidence * 80) + (annualPotential / 150) + (marginItem.gross_margin_percentage * 1.5)
                        });
                    }
                }
            });
        
        // 3. SLEEPING GIANTS - A-category products performing below potential
        if (abcData && abcData.length > 0) {
            abcData
                .filter((item: any) => item.category === 'A')
                .forEach((abcItem: any) => {
                    if (!processedSkus.has(abcItem.sku)) {
                        const velocityItem = velocityData.find((v: any) => v.sku === abcItem.sku);
                        const marginItem = marginData.find((m: any) => m.sku === abcItem.sku);
                        const turnoverItem = turnoverData?.find((t: any) => t.sku === abcItem.sku);
                        
                        if (velocityItem && marginItem && turnoverItem && turnoverItem.turnover_ratio < 3) {
                            processedSkus.add(abcItem.sku);
                            
                            const currentVelocity = velocityItem.daily_velocity;
                            const optimalVelocity = Math.max(currentVelocity * 1.8, 3.0); // Conservative for A-products
                            const monthlyLift = (optimalVelocity - currentVelocity) * 30 * (marginItem.revenue / marginItem.quantity_sold);
                            const annualPotential = monthlyLift * 12;
                            
                            opportunities.push({
                                sku: abcItem.sku,
                                product_name: abcItem.product_name,
                                opportunity_type: 'Sleeping Giant',
                                priority: 'High',
                                current_performance: {
                                    daily_velocity: currentVelocity,
                                    margin_percentage: marginItem.gross_margin_percentage,
                                    revenue_category: 'A-Class (Top 20%)',
                                    turnover_ratio: turnoverItem.turnover_ratio,
                                    revenue_contribution: abcItem.revenue_contribution
                                },
                                opportunity_metrics: {
                                    potential_daily_velocity: optimalVelocity,
                                    category_rank: abcItem.rank,
                                    monthly_revenue_lift: monthlyLift,
                                    annual_revenue_potential: annualPotential,
                                    confidence_score: 0.85 // High confidence for A-products
                                },
                                ai_insights: {
                                    primary_opportunity: 'Top revenue product with optimization potential',
                                    performance_gap: 'Below-optimal turnover for A-category product',
                                    strategic_importance: 'Core revenue driver - high optimization impact',
                                    market_position: `Rank #${abcItem.rank} in revenue contribution`
                                },
                                recommended_actions: [
                                    {
                                        action: 'Optimize inventory turnover strategy',
                                        impact: 'High',
                                        timeline: '2-3 weeks',
                                        investment: 'Medium - process optimization',
                                        expected_lift: '60-120%'
                                    },
                                    {
                                        action: 'Enhance product visibility and placement',
                                        impact: 'High',
                                        timeline: '1 week',
                                        investment: 'Low - positioning only',
                                        expected_lift: '40-80%'
                                    },
                                    {
                                        action: 'Implement dynamic pricing strategy',
                                        impact: 'Medium',
                                        timeline: '1-2 weeks',
                                        investment: 'Low - pricing tools',
                                        expected_lift: '20-40%'
                                    }
                                ],
                                financial_impact: {
                                    investment_needed: 600,
                                    roi_estimate: 9.2,
                                    payback_period_months: 1.5,
                                    risk_level: 'Low'
                                },
                                opportunity_score: 90 + (annualPotential / 100) + (marginItem.gross_margin_percentage * 1.2)
                            });
                        }
                    }
                });
        }
        
        // 4. CROSS-SELL MAXIMIZERS - High-velocity products with cross-sell potential
        velocityData
            .filter((item: any) => item.velocity_category === 'fast' && item.daily_velocity > 2)
            .forEach((velocityItem: any) => {
                if (!processedSkus.has(velocityItem.sku)) {
                    const marginItem = marginData.find((m: any) => m.sku === velocityItem.sku);
                    
                    if (marginItem && marginItem.gross_margin_percentage > 30) {
                        processedSkus.add(velocityItem.sku);
                        
                        const crossSellMultiplier = 1.4; // Conservative cross-sell lift
                        const currentRevenue = velocityItem.daily_velocity * 30 * (marginItem.revenue / marginItem.quantity_sold);
                        const crossSellRevenue = currentRevenue * (crossSellMultiplier - 1);
                        const annualPotential = crossSellRevenue * 12;
                        
                        opportunities.push({
                            sku: velocityItem.sku,
                            product_name: velocityItem.product_name,
                            opportunity_type: 'Cross-Sell Maximizer',
                            priority: 'Medium',
                            current_performance: {
                                daily_velocity: velocityItem.daily_velocity,
                                velocity_category: velocityItem.velocity_category,
                                margin_percentage: marginItem.gross_margin_percentage,
                                monthly_revenue: currentRevenue,
                                performance_status: 'High velocity'
                            },
                            opportunity_metrics: {
                                cross_sell_multiplier: crossSellMultiplier,
                                monthly_revenue_lift: crossSellRevenue,
                                annual_revenue_potential: annualPotential,
                                confidence_score: 0.75
                            },
                            ai_insights: {
                                primary_opportunity: 'High-traffic product ideal for cross-selling',
                                customer_behavior: 'Strong purchase velocity indicates customer appeal',
                                strategic_value: 'Gateway product for ecosystem expansion',
                                optimization_focus: 'Leverage existing momentum for related sales'
                            },
                            recommended_actions: [
                                {
                                    action: 'Create product bundles with complementary items',
                                    impact: 'Medium',
                                    timeline: '1 week',
                                    investment: 'Low - bundling strategy',
                                    expected_lift: '25-50%'
                                },
                                {
                                    action: 'Implement "frequently bought together" recommendations',
                                    impact: 'Medium',
                                    timeline: '2 weeks',
                                    investment: 'Medium - recommendation engine',
                                    expected_lift: '30-60%'
                                },
                                {
                                    action: 'Develop upsell pathways to premium versions',
                                    impact: 'Low',
                                    timeline: '3 weeks',
                                    investment: 'Low - product positioning',
                                    expected_lift: '15-25%'
                                }
                            ],
                            financial_impact: {
                                investment_needed: 300,
                                roi_estimate: 5.8,
                                payback_period_months: 2.8,
                                risk_level: 'Low'
                            },
                            opportunity_score: 60 + (annualPotential / 200) + (velocityItem.daily_velocity * 5)
                        });
                    }
                }
            });
        
        // Sort by opportunity score and add ranking
        const sortedOpportunities = opportunities
            .sort((a, b) => b.opportunity_score - a.opportunity_score)
            .slice(0, 15) // Top 15 opportunities
            .map((opp, index) => ({
                ...opp,
                opportunity_rank: index + 1,
                total_potential_annual_revenue: opportunities.reduce((sum, o) => sum + o.opportunity_metrics.annual_revenue_potential, 0),
                implementation_complexity: opp.recommended_actions.length > 2 ? 'Medium' : 'Low'
            }));
        
        return sortedOpportunities;
        
    } catch (error) {
        logError(error, { context: 'getHiddenRevenueOpportunitiesFromDB unexpected error' });
        return [];
    }
}

export async function getSupplierPerformanceScoreFromDB(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    // Get supplier performance data
    const { data: suppliers, error: suppliersError } = await supabase
        .from('suppliers')
        .select(`
            id,
            name,
            contact_email,
            product_variants(
                id,
                sku,
                cost,
                inventory_quantity,
                reorder_point
            )
        `)
        .eq('company_id', companyId);
    
    if (suppliersError) {
        logError(suppliersError, { context: 'getSupplierPerformanceScoreFromDB failed' });
        throw suppliersError;
    }
    
    // Calculate performance scores
    const performanceData = suppliers?.map((supplier: any) => {
        const products = supplier.product_variants || [];
        const totalProducts = products.length;
        const lowStockCount = products.filter((p: any) => p.inventory_quantity <= (p.reorder_point || 0)).length;
        const avgCost = products.reduce((sum: number, p: any) => sum + (p.cost || 0), 0) / Math.max(1, totalProducts);
        
        // Simple scoring algorithm
        const stockScore = totalProducts > 0 ? ((totalProducts - lowStockCount) / totalProducts) * 100 : 50;
        const costScore = avgCost > 0 ? Math.min(100, (1000 / avgCost) * 10) : 50; // Lower cost = higher score
        const reliabilityScore = 85; // Placeholder - could be based on delivery history
        
        const overallScore = (stockScore * 0.4 + costScore * 0.3 + reliabilityScore * 0.3);
        
        return {
            supplier_id: supplier.id,
            supplier_name: supplier.name,
            contact_email: supplier.contact_email,
            total_products: totalProducts,
            low_stock_products: lowStockCount,
            average_cost: avgCost,
            stock_performance_score: Math.round(stockScore),
            cost_performance_score: Math.round(costScore),
            reliability_score: Math.round(reliabilityScore),
            overall_score: Math.round(overallScore),
            performance_grade: overallScore >= 80 ? 'A' : overallScore >= 60 ? 'B' : 'C',
            recommendation: overallScore >= 80 
                ? 'Excellent supplier - maintain partnership'
                : overallScore >= 60 
                ? 'Good supplier - monitor performance'
                : 'Consider alternative suppliers'
        };
    }) || [];
    
    return performanceData.sort((a, b) => b.overall_score - a.overall_score);
}

export async function getInventoryTurnoverAnalysisFromDB(companyId: string, days: number = 365) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    // Get inventory data without complex joins
    const { data: variants, error: variantsError } = await supabase
        .from('product_variants')
        .select(`
            sku,
            title,
            cost,
            inventory_quantity
        `)
        .eq('company_id', companyId);
    
    if (variantsError) {
        logError(variantsError, { context: 'getInventoryTurnoverAnalysisFromDB failed' });
        return null;
    }

    if (!variants || variants.length === 0) {
        return [];
    }

    // Get order line items separately
    const { data: orderItems, error: orderError } = await supabase
        .from('order_line_items')
        .select(`
            sku,
            quantity
        `)
        .eq('company_id', companyId);

    if (orderError) {
        logError(orderError, { context: 'getInventoryTurnoverAnalysisFromDB order items failed' });
        return [];
    }
    
    const turnoverData = variants.map((variant: any) => {
        const recentSales = orderItems
            ?.filter((oli: any) => oli.sku === variant.sku)
            ?.reduce((sum: number, oli: any) => sum + oli.quantity, 0) || 0;
        
        const avgInventory = variant.inventory_quantity || 0;
        const cogs = recentSales * (variant.cost || 0);
        const inventoryValue = avgInventory * (variant.cost || 0);
        
        const turnoverRatio = inventoryValue > 0 ? cogs / inventoryValue : 0;
        const daysSalesInInventory = turnoverRatio > 0 ? days / turnoverRatio : 999;
        
        let performance = 'Poor';
        if (turnoverRatio > 6) performance = 'Excellent';
        else if (turnoverRatio > 4) performance = 'Good';
        else if (turnoverRatio > 2) performance = 'Fair';
        
        return {
            sku: variant.sku,
            product_name: variant.title || 'Unknown',
            current_inventory: avgInventory,
            units_sold: recentSales,
            inventory_value: inventoryValue,
            cogs: cogs,
            turnover_ratio: Math.round(turnoverRatio * 100) / 100,
            days_sales_in_inventory: Math.round(daysSalesInInventory),
            performance_rating: performance,
            recommendation: turnoverRatio > 6 
                ? 'Optimal turnover - maintain current levels'
                : turnoverRatio > 2
                ? 'Good turnover - monitor for optimization'
                : turnoverRatio > 0.5
                ? 'Slow turnover - consider promotion or markdown'
                : 'Very slow/no turnover - review necessity'
        };
    }) || [];
    
    return turnoverData
        .filter((item: any) => item.inventory_value > 0)
        .sort((a, b) => b.turnover_ratio - a.turnover_ratio);
}

export async function getCustomerBehaviorInsightsFromDB(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    // Get customer purchase patterns
    const { data, error } = await supabase
        .from('customers')
        .select(`
            id,
            name,
            email,
            created_at,
            orders(
                id,
                total_amount,
                created_at,
                financial_status,
                order_line_items(
                    sku,
                    product_name,
                    quantity,
                    price
                )
            )
        `)
        .eq('company_id', companyId);
    
    if (error) {
        logError(error, { context: 'getCustomerBehaviorInsightsFromDB failed' });
        throw error;
    }
    
    const insights = data?.map((customer: any) => {
        const orders = customer.orders?.filter((o: any) => o.financial_status === 'paid') || [];
        const totalSpent = orders.reduce((sum: number, order: any) => sum + order.total_amount, 0);
        const avgOrderValue = orders.length > 0 ? totalSpent / orders.length : 0;
        
        // Calculate customer lifetime value and segment
        const daysSinceFirstOrder = orders.length > 0 
            ? Math.max(1, (Date.now() - new Date(orders[0].created_at).getTime()) / (1000 * 60 * 60 * 24))
            : 0;
        
        const purchaseFrequency = daysSinceFirstOrder > 0 ? orders.length / (daysSinceFirstOrder / 30) : 0; // orders per month
        
        let segment = 'New';
        if (totalSpent > 1000 && purchaseFrequency > 1) segment = 'VIP';
        else if (totalSpent > 500 || purchaseFrequency > 0.5) segment = 'Regular';
        else if (orders.length > 0) segment = 'Occasional';
        
        // Get product preferences
        const productFrequency = new Map();
        orders.forEach((order: any) => {
            order.order_line_items?.forEach((item: any) => {
                const category = item.product_name?.split(' ')[0] || 'Unknown';
                productFrequency.set(category, (productFrequency.get(category) || 0) + item.quantity);
            });
        });
        
        const topCategory = Array.from(productFrequency.entries())
            .sort(([,a], [,b]) => b - a)[0]?.[0] || 'Unknown';
        
        return {
            customer_id: customer.id,
            customer_name: customer.name,
            email: customer.email,
            segment,
            total_orders: orders.length,
            total_spent: totalSpent,
            average_order_value: avgOrderValue,
            purchase_frequency_per_month: Math.round(purchaseFrequency * 100) / 100,
            days_since_first_order: Math.round(daysSinceFirstOrder),
            preferred_category: topCategory,
            customer_lifetime_value: totalSpent + (avgOrderValue * purchaseFrequency * 12), // Projected CLV
            recommendation: segment === 'VIP' 
                ? 'Offer exclusive products and early access'
                : segment === 'Regular'
                ? 'Engage with loyalty programs and personalized offers'
                : segment === 'Occasional'
                ? 'Re-engagement campaigns and targeted promotions'
                : 'Welcome series and first-purchase incentives'
        };
    }) || [];
    
    return insights.sort((a, b) => b.customer_lifetime_value - a.customer_lifetime_value);
}

export async function getMultiChannelFeeAnalysisFromDB(companyId: string) {
    if (!z.string().uuid().safeParse(companyId).success) throw new Error('Invalid Company ID');
    const supabase = getServiceRoleClient();
    
    // Get sales by channel with fee analysis
    const { data: orders, error: ordersError } = await supabase
        .from('orders')
        .select(`
            source_platform,
            total_amount,
            financial_status,
            order_line_items(
                quantity,
                price,
                cost_at_time
            )
        `)
        .eq('company_id', companyId)
        .eq('financial_status', 'paid');
    
    if (ordersError) {
        logError(ordersError, { context: 'getMultiChannelFeeAnalysisFromDB failed' });
        throw ordersError;
    }
    
    // Get channel fees
    const { data: fees, error: feesError } = await supabase
        .from('channel_fees')
        .select('*')
        .eq('company_id', companyId);
    
    if (feesError) {
        logError(feesError, { context: 'getMultiChannelFeeAnalysisFromDB channel fees failed' });
        // Continue without fees if table doesn't exist
    }
    
    // Default fee structure
    const defaultFees: { [key: string]: { percentage: number, fixed: number } } = {
        'shopify': { percentage: 2.9, fixed: 0.30 },
        'amazon': { percentage: 15.0, fixed: 0 },
        'woocommerce': { percentage: 2.9, fixed: 0.30 },
        'manual': { percentage: 0, fixed: 0 },
        'other': { percentage: 3.5, fixed: 0.30 }
    };
    
    // Merge with custom fees
    const feeStructure = { ...defaultFees };
    fees?.forEach((fee: any) => {
        feeStructure[fee.channel_name.toLowerCase()] = {
            percentage: fee.percentage_fee || fee.fee_percentage || 0,
            fixed: fee.fixed_fee || 0
        };
    });
    
    // Analyze by channel
    const channelData = new Map();
    
    orders?.forEach((order: any) => {
        const channel = (order.source_platform || 'manual').toLowerCase();
        const revenue = order.total_amount || 0;
        const cost = order.order_line_items?.reduce((sum: number, item: any) => 
            sum + (item.quantity * (item.cost_at_time || 0)), 0) || 0;
        
        if (!channelData.has(channel)) {
            channelData.set(channel, {
                channel_name: channel,
                order_count: 0,
                total_revenue: 0,
                total_cost: 0,
                total_fees: 0
            });
        }
        
        const data = channelData.get(channel);
        const fees = feeStructure[channel] || feeStructure.other;
        const channelFees = (revenue * fees.percentage / 100) + fees.fixed;
        
        data.order_count += 1;
        data.total_revenue += revenue;
        data.total_cost += cost;
        data.total_fees += channelFees;
    });
    
    const result = Array.from(channelData.values()).map((data: any) => ({
        ...data,
        gross_profit: data.total_revenue - data.total_cost,
        net_profit: data.total_revenue - data.total_cost - data.total_fees,
        fee_percentage: data.total_revenue > 0 ? (data.total_fees / data.total_revenue) * 100 : 0,
        profit_margin: data.total_revenue > 0 ? ((data.total_revenue - data.total_cost - data.total_fees) / data.total_revenue) * 100 : 0,
        average_order_value: data.order_count > 0 ? data.total_revenue / data.order_count : 0,
        profitability_rank: 0 // Will be set after sorting
    }));
    
    // Sort by net profit and assign ranks
    result.sort((a, b) => b.net_profit - a.net_profit);
    result.forEach((item, index) => {
        item.profitability_rank = index + 1;
    });
    
    return result;
}
