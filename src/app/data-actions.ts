
'use server';
import { getAuthContext, getCurrentUser } from '@/lib/auth-helpers';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import {
    getDeadStockReportFromDB,
    getSupplierByIdFromDB,
    createSupplierInDb,
    updateSupplierInDb,
    deleteSupplierFromDb,
    getIntegrationsByCompanyId,
    deleteIntegrationFromDb,
    getTeamMembersFromDB,
    inviteUserToCompanyInDb,
    removeTeamMemberFromDb,
    updateTeamMemberRoleInDb,
    getCompanyById,
    getSettings,
    updateSettingsInDb,
    getUnifiedInventoryFromDB,
    getInventoryAnalyticsFromDB,
    getSuppliersDataFromDB,
    getCustomersFromDB,
    deleteCustomerFromDb,
    getSalesFromDB,
    getSalesAnalyticsFromDB,
    getCustomerAnalyticsFromDB,
    createPurchaseOrderInDb,
    getPurchaseOrdersFromDB,
    updatePurchaseOrderInDb,
    getPurchaseOrderByIdFromDB,
    getInventoryLedgerFromDB,
    getChannelFeesFromDB,
    upsertChannelFeeInDb,
    createExportJobInDb,
    reconcileInventoryInDb,
    getDashboardMetrics as getDashboardMetricsFromDb,
    checkUserPermission,
    getHistoricalSalesForSkus,
    createAuditLogInDb as createAuditLogInDbService,
    adjustInventoryQuantityInDb,
    getAuditLogFromDB,
    getFeedbackFromDB,
    deletePurchaseOrderFromDb,
    getSupplierPerformanceFromDB,
    getInventoryTurnoverFromDB,
    getAbcAnalysisFromDB,
    getSalesVelocityFromDB,
    getGrossMarginAnalysisFromDB,
    createPurchaseOrdersFromSuggestionsInDb,
    logUserFeedbackInDb as logUserFeedbackInDbService
} from '@/services/database';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import type { DashboardMetrics, PurchaseOrderFormData, ChannelFee, AuditLogEntry, FeedbackWithMessages } from '@/types';
import { SupplierFormSchema } from '@/schemas/suppliers';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { Message, Conversation, CustomerAnalytics, ReorderSuggestion } from '@/types';
import { z } from 'zod';
import { isRedisEnabled, redisClient } from '@/lib/redis';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { revalidatePath } from 'next/cache';
import type { Json } from '@/types/database.types';


export async function getProducts() {
  const { companyId } = await getAuthContext();
  const { items } = await getUnifiedInventoryFromDB(companyId, {});
  return items;
}

export async function getOrders() {
  const { companyId } = await getAuthContext();
  const { items } = await getSalesFromDB(companyId, { offset: 0, limit: 1000});
  return items;
}

export async function getCustomers() {
  const { companyId } = await getAuthContext();
  const { items } = await getCustomersFromDB(companyId, { offset: 0, limit: 1000});
  return items;
}

export async function getUnifiedInventory(params: { query: string, page: number, limit: number, status: string, sortBy: string, sortDirection: string }) {
    try {
        const { companyId } = await getAuthContext();
        const offset = (params.page - 1) * params.limit;
        return await getUnifiedInventoryFromDB(companyId, { ...params, offset });
    } catch (e) {
        logError(e, {context: 'getUnifiedInventory action failed, returning empty state'});
        return { items: [], totalCount: 0 };
    }
}

export async function getInventoryAnalytics() {
    try {
        const { companyId } = await getAuthContext();
        const cacheKey = `cache:inventory-analytics:${companyId}`;
        if(isRedisEnabled) {
            const cached = await redisClient.get(cacheKey);
            if(cached) return JSON.parse(cached);
        }
        const analytics = await getInventoryAnalyticsFromDB(companyId);
        if(isRedisEnabled) await redisClient.set(cacheKey, JSON.stringify(analytics), 'EX', config.redis.ttl.dashboard);
        return analytics;
    } catch (e) {
        logError(e, {context: 'getInventoryAnalytics action failed, returning default'});
        return { total_inventory_value: 0, total_products: 0, total_variants: 0, low_stock_items: 0 };
    }
}

export async function getSuppliersData() {
    const { companyId } = await getAuthContext();
    return await getSuppliersDataFromDB(companyId);
}

export async function getSupplierById(id: string) {
    const { companyId } = await getAuthContext();
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const data = SupplierFormSchema.parse(Object.fromEntries(formData.entries()));
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const data = SupplierFormSchema.parse(Object.fromEntries(formData.entries()));
        await updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const id = formData.get('id') as string;
        await deleteSupplierFromDb(id, companyId);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getIntegrations() {
    const { companyId } = await getAuthContext();
    return getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);
        const id = formData.get('integrationId') as string;
        await deleteIntegrationFromDb(id, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getTeamMembers() {
    const { companyId } = await getAuthContext();
    return getTeamMembersFromDB(companyId);
}

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);
        const email = formData.get('email') as string;
        const company = await getCompanyById(companyId);
        await inviteUserToCompanyInDb(companyId, company?.name || 'your company', email);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function removeTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        const memberId = formData.get('memberId') as string;
        if (userId === memberId) throw new Error("You cannot remove yourself.");
        
        const members = await getTeamMembersFromDB(companyId);
        const currentUser = members.find(m => m.id === userId);
        const memberToRemove = members.find(m => m.id === memberId);

        if (currentUser?.role === 'Owner') {
            // Owners can remove anyone but themselves
        } else if (currentUser?.role === 'Admin') {
            // Admins can only remove Members
            if (memberToRemove?.role === 'Admin' || memberToRemove?.role === 'Owner') {
                throw new Error("Admins cannot remove other Admins or Owners.");
            }
        } else {
            // Members can't remove anyone
            throw new Error("You do not have permission to remove team members.");
        }

        await removeTeamMemberFromDb(memberId, companyId);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Owner');
        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member' | 'Owner';
        if (!['Admin', 'Member', 'Owner'].includes(newRole)) throw new Error('Invalid role specified.');
        if (userId === memberId) throw new Error("You cannot change your own role.");
        
        await updateTeamMemberRoleInDb(memberId, companyId, newRole);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCompanySettings() {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);
        const settings = {
            dead_stock_days: Number(formData.get('dead_stock_days')),
            fast_moving_days: Number(formData.get('fast_moving_days')),
            overstock_multiplier: Number(formData.get('overstock_multiplier')),
            high_value_threshold: Number(formData.get('high_value_threshold')),
            currency: String(formData.get('currency')),
            timezone: String(formData.get('timezone')),
        }
        await updateSettingsInDb(companyId, settings);
        await createAuditLogInDbService(companyId, userId, 'company_settings_updated', settings);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSalesData(params: { query: string; page: number, limit: number }) {
    try {
        const { companyId } = await getAuthContext();
        const offset = (params.page - 1) * params.limit;
        return await getSalesFromDB(companyId, { ...params, offset });
    } catch(e) {
        logError(e, {context: 'getSalesData action failed, returning empty state'});
        return { items: [], totalCount: 0 };
    }
}

export async function exportSales(params: { query: string }) {
    try {
        const { companyId } = await getAuthContext();
        // Fetch all customers matching the query, up to a reasonable limit.
        const { items } = await getSalesFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSalesAnalytics(): Promise<SalesAnalytics> {
    try {
        const { companyId } = await getAuthContext();
        const cacheKey = `cache:sales-analytics:${companyId}`;
        if(isRedisEnabled) {
            const cached = await redisClient.get(cacheKey);
            if(cached) return JSON.parse(cached);
        }
        const analytics = await getSalesAnalyticsFromDB(companyId);
        if(isRedisEnabled) await redisClient.set(cacheKey, JSON.stringify(analytics), 'EX', config.redis.ttl.dashboard);
        return analytics;
    } catch (e) {
        logError(e, {context: 'getSalesAnalytics action failed, returning default'});
        return { total_revenue: 0, total_orders: 0, average_order_value: 0 };
    }
}

export async function getCustomersData(params: { query: string; page: number, limit: number }) {
    try {
        const { companyId } = await getAuthContext();
        const offset = (params.page - 1) * params.limit;
        return await getCustomersFromDB(companyId, { ...params, offset });
    } catch (e) {
        logError(e, {context: 'getCustomersData action failed, returning empty state'});
        return { items: [], totalCount: 0 };
    }
}

export async function deleteCustomer(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const customerId = formData.get('id') as string;
        await deleteCustomerFromDb(customerId, companyId);
        revalidatePath('/customers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function exportCustomers(params: { query: string }) {
    try {
        const { companyId } = await getAuthContext();
        // Fetch all customers matching the query, up to a reasonable limit.
        const { items } = await getCustomersFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        logError(e, { context: 'exportCustomers failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCustomerAnalytics(): Promise<CustomerAnalytics> {
    try {
        const { companyId } = await getAuthContext();
        const cacheKey = `cache:customer-analytics:${companyId}`;
        if(isRedisEnabled) {
            const cached = await redisClient.get(cacheKey);
            if(cached) {
                logger.info(`[Cache] HIT for customer analytics: ${cacheKey}`);
                return JSON.parse(cached);
            }
             logger.info(`[Cache] MISS for customer analytics: ${cacheKey}`);
        }
        
        const rawAnalytics = await getCustomerAnalyticsFromDB(companyId);
        
        const analyticsData = Array.isArray(rawAnalytics) ? rawAnalytics[0] : rawAnalytics;

        if (!analyticsData) {
            throw new Error("Customer analytics data is null or undefined after DB call.");
        }

        if(isRedisEnabled) {
            await redisClient.set(cacheKey, JSON.stringify(analyticsData), 'EX', config.redis.ttl.dashboard);
        }
        
        return analyticsData;
    } catch (e) {
        logError(e, {context: 'getCustomerAnalytics action failed, returning default'});
        return { total_customers: 0, new_customers_last_30_days: 0, repeat_customer_rate: 0, average_lifetime_value: 0, top_customers_by_spend: [], top_customers_by_sales: [] };
    }
}

export async function exportInventory(params: { query: string; status: string; sortBy: string; sortDirection: string; }) {
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        
        const dataToExport = items.map(item => ({
            product_title: item.product_title,
            variant_title: item.title,
            sku: item.sku,
            inventory_quantity: item.inventory_quantity,
            price_dollars: item.price ? (item.price / 100).toFixed(2) : '0.00',
            cost_dollars: item.cost ? (item.cost / 100).toFixed(2) : '0.00',
            product_status: item.product_status,
            product_type: item.product_type,
            location: item.location,
            barcode: item.barcode,
        })) || [];
        
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        logError(e, { context: 'exportInventory failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getPurchaseOrders() {
    try {
        const { companyId } = await getAuthContext();
        return await getPurchaseOrdersFromDB(companyId);
    } catch (e) {
        logError(e, {context: 'getPurchaseOrders action failed, returning empty state'});
        return [];
    }
}

export async function getPurchaseOrderById(id: string) {
    const { companyId } = await getAuthContext();
    const po = await getPurchaseOrderByIdFromDB(id, companyId);
    if (!po) return null;

    // Manually map to camelCase for the form
    return {
        ...po,
        supplier_id: po.supplier_id,
        po_number: po.po_number,
        total_cost: po.total_cost,
        expected_arrival_date: po.expected_arrival_date,
        line_items: po.line_items?.map((item: any) => ({
            variant_id: item.variant_id,
            quantity: item.quantity,
            cost: item.cost,
        })) || []
    }
}

export async function createPurchaseOrder(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const data: PurchaseOrderFormData = JSON.parse(formData.get('data') as string);
        const newPoId = await createPurchaseOrderInDb(companyId, userId, data);
        revalidatePath('/purchase-orders');
        return { success: true, newPoId };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updatePurchaseOrder(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const id = formData.get('id') as string;
        const data: PurchaseOrderFormData = JSON.parse(formData.get('data') as string);
        await updatePurchaseOrderInDb(id, companyId, userId, data);
        revalidatePath('/purchase-orders');
        return { success: true, updatedPoId: id };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deletePurchaseOrder(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const id = formData.get('id') as string;
        await deletePurchaseOrderFromDb(id, companyId);
        revalidatePath('/purchase-orders');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function createPurchaseOrdersFromSuggestions(suggestions: ReorderSuggestion[]): Promise<{ success: boolean; createdPoCount?: number; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        const createdPoCount = await createPurchaseOrdersFromSuggestionsInDb(companyId, userId, suggestions);
        revalidatePath('/purchase-orders');
        revalidatePath('/analytics/reordering');
        return { success: true, createdPoCount };
    } catch (e) {
        logError(e, { context: 'createPurchaseOrdersFromSuggestions failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function getInventoryLedger(variantId: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerFromDB(companyId, variantId);
}

export async function getChannelFees() {
    const { companyId } = await getAuthContext();
    return getChannelFeesFromDB(companyId);
}

export async function upsertChannelFee(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);
        const data: Partial<ChannelFee> = {
            channel_name: formData.get('channel_name') as string,
            fixed_fee: Number(formData.get('fixed_fee')) || null,
            percentage_fee: Number(formData.get('percentage_fee')) || null,
        }
        await upsertChannelFeeInDb(companyId, data);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function requestCompanyDataExport(): Promise<{ success: boolean, error?: string, jobId?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        const job = await createExportJobInDb(companyId, userId);
        return { success: true, jobId: job.id };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function reconcileInventory(integrationId: string) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await reconcileInventoryInDb(companyId, integrationId, userId);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getDashboardData(dateRange: string): Promise<DashboardMetrics> {
    const { companyId } = await getAuthContext();
    const cacheKey = `cache:dashboard:${dateRange}:${companyId}`;

    if (isRedisEnabled) {
        try {
            const cached = await redisClient.get(cacheKey);
            if (cached) {
                logger.info(`[Cache] HIT for dashboard metrics: ${cacheKey}`);
                return JSON.parse(cached);
            }
            logger.info(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
        } catch (e) {
            logError(e, { context: 'Redis cache get failed for dashboard' });
        }
    }

    try {
        const data = await getDashboardMetricsFromDb(companyId, dateRange);
        if (isRedisEnabled && data) {
          await redisClient.set(cacheKey, JSON.stringify(data), 'EX', config.redis.ttl.dashboard);
        }
        return data ?? { total_revenue: 0, revenue_change: 0, total_orders: 0, orders_change: 0, new_customers: 0, customers_change: 0, dead_stock_value: 0, sales_over_time: [], top_products: [], inventory_summary: { total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0 } };
    } catch (e) {
        logError(e, { context: 'Failed to fetch dashboard data from database RPC' });
        return { total_revenue: 0, revenue_change: 0, total_orders: 0, orders_change: 0, new_customers: 0, customers_change: 0, dead_stock_value: 0, sales_over_time: [], top_products: [], inventory_summary: { total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0 } };
    }
}

export async function getMorningBriefing(metrics: DashboardMetrics, companyName?: string) {
    return generateMorningBriefing({ metrics, companyName });
}

export async function getSupplierPerformanceReportData() {
    try {
        const { companyId } = await getAuthContext();
        return await getSupplierPerformanceFromDB(companyId);
    } catch(e) {
        logError(e, { context: 'getSupplierPerformanceReportData failed, returning empty array'});
        return [];
    }
}

export async function getInventoryTurnoverReportData() {
    try {
        const { companyId } = await getAuthContext();
        return await getInventoryTurnoverFromDB(companyId, 90);
    } catch(e) {
        logError(e, { context: 'getInventoryTurnoverReportData failed, returning null'});
        return null;
    }
}

export async function getConversations(): Promise<Conversation[]> {
    const user = await getCurrentUser();
    if (!user) return [];
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('conversations')
        .select('*')
        .eq('user_id', user.id)
        .order('last_accessed_at', { ascending: false });
    if(error) {
        logError(error, {context: 'getConversations failed'});
        return [];
    }
    return data || [];
}

export async function getMessages(conversationId: string): Promise<Message[]> {
    const user = await getCurrentUser();
    if (!user) return [];
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('messages')
        .select(`
            id,
            conversation_id,
            company_id,
            role,
            content,
            visualization,
            component,
            component_props,
            confidence,
            assumptions,
            created_at,
            is_error
        `)
        .eq('conversation_id', conversationId)
        .order('created_at', { ascending: true });
    
    if (error) {
        logError(error, {context: 'getMessages failed'});
        return [];
    }
    return (data as Message[]) || [];
}

const chatInputSchema = z.object({
  content: z.string().min(1, "Message cannot be empty.").max(2000, "Message cannot exceed 2000 characters."),
  conversationId: z.string().uuid("Invalid conversation ID.").nullable(),
});


export async function handleUserMessage(params: { content: string, conversationId: string | null }): Promise<{ newMessage?: Message, conversationId?: string, error?: string }> {
  try {
    const { companyId, userId } = await getAuthContext();
    const validatedInput = chatInputSchema.parse(params);
    let { content, conversationId } = validatedInput;

    const supabase = getServiceRoleClient();
    
    if (!conversationId) {
        const { data: newConversation, error: convError } = await supabase.from('conversations').insert({
            user_id: userId,
            company_id: companyId,
            title: content.substring(0, 50)
        }).select().single();
        if(convError) throw convError;
        conversationId = newConversation.id;
    }


    await supabase.from('messages').insert({
        conversation_id: conversationId,
        company_id: companyId,
        role: 'user',
        content,
    });
    
    const { data: history } = await supabase.from('messages').select('*').eq('conversation_id', conversationId).order('created_at', { ascending: false }).limit(10);
    const reversedHistory = (history || []).reverse();

    const aiResponse = await universalChatFlow({
        companyId: companyId,
        conversationHistory: reversedHistory.map(m => ({ 
            role: m.role as 'user' | 'model', 
            content: [{ text: m.content }] 
        })) || [],
    });

    const { data: newMessage, error: messageError } = await supabase.from('messages').insert({
        conversation_id: conversationId,
        company_id: companyId,
        role: 'assistant',
        content: aiResponse.response,
        visualization: aiResponse.visualization as any,
        component: aiResponse.toolName,
        component_props: aiResponse.data as any,
        confidence: aiResponse.confidence,
        assumptions: aiResponse.assumptions,
        is_error: aiResponse.is_error,
    }).select(`
      id,
      conversation_id,
      company_id,
      role,
      content,
      visualization,
      component,
      component_props,
      confidence,
      assumptions,
      created_at,
      is_error
    `).single();
    
    if (messageError) throw messageError;

    return { newMessage: newMessage as Message, conversationId: conversationId };

  } catch(e) {
    const errorMessage = getErrorMessage(e);
    logError(e, {context: 'handleUserMessage failed'});
    return { error: errorMessage };
  }
}

export async function logUserFeedbackInDb(params: { subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful' }) {
    try {
        const { companyId, userId } = await getAuthContext();
        await logUserFeedbackInDbService(userId, companyId, params.subjectId, params.subjectType, params.feedback);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getDeadStockReport() {
    try {
        const { companyId } = await getAuthContext();
        return await getDeadStockReportFromDB(companyId);
    } catch(e) {
        logError(e, { context: 'getDeadStockReport failed, returning default'});
        return { deadStockItems: [], totalValue: 0, totalUnits: 0 };
    }
}

export async function getAdvancedAbcReport() {
    try {
        const { companyId } = await getAuthContext();
        return await getAbcAnalysisFromDB(companyId);
    } catch(e) {
        logError(e, { context: 'getAdvancedAbcReport failed, returning null'});
        return null;
    }
}

export async function getAdvancedSalesVelocityReport() {
    try {
        const { companyId } = await getAuthContext();
        return await getSalesVelocityFromDB(companyId, 90, 20);
    } catch(e) {
        logError(e, { context: 'getAdvancedSalesVelocityReport failed, returning null'});
        return { fast_sellers: [], slow_sellers: [] };
    }
}

export async function getAdvancedGrossMarginReport() {
    try {
        const { companyId } = await getAuthContext();
        return await getGrossMarginAnalysisFromDB(companyId);
    } catch(e) {
        logError(e, { context: 'getAdvancedGrossMarginReport failed, returning null'});
        return { products: [], summary: { total_revenue: 0, total_cogs: 0, total_gross_margin: 0, average_gross_margin: 0 } };
    }
}

export async function adjustInventoryQuantity(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);

        const variantId = formData.get('variantId') as string;
        const newQuantity = Number(formData.get('newQuantity'));
        const reason = formData.get('reason') as string;

        await adjustInventoryQuantityInDb(companyId, userId, variantId, newQuantity, reason);

        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getImportHistory() {
    const { companyId, userId } = await getAuthContext();
    await checkUserPermission(userId, 'Admin');
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.from('imports').select('*').eq('company_id', companyId).order('created_at', { ascending: false }).limit(20);
    if(error) throw error;
    return data;
}

export async function getAuditLogData(params: {
  page: number;
  limit: number;
  query?: string;
}): Promise<{ items: AuditLogEntry[]; totalCount: number }> {
  try {
    const { companyId, userId } = await getAuthContext();
    await checkUserPermission(userId, 'Admin');

    const offset = (params.page - 1) * params.limit;
    return getAuditLogFromDB(companyId, { ...params, offset });
  } catch (error) {
    logError(error, { context: 'getAuditLogData failed' });
    return { items: [], totalCount: 0 };
  }
}

export async function getFeedbackData(params: {
  page: number;
  limit: number;
  query?: string;
}): Promise<{ items: FeedbackWithMessages[]; totalCount: number }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');

        const offset = (params.page - 1) * params.limit;
        return getFeedbackFromDB(companyId, { ...params, offset });
    } catch (error) {
        logError(error, { context: 'getFeedbackData failed' });
        return { items: [], totalCount: 0 };
    }
}
export async function createPurchaseOrdersFromSuggestions(suggestions: ReorderSuggestion[]) {
    const { companyId, userId } = await getAuthContext();
    const createdPoCount = await createPurchaseOrdersFromSuggestionsInDb(companyId, userId, suggestions);
    revalidatePath('/purchase-orders');
    revalidatePath('/analytics/reordering');
    return { success: true, createdPoCount };
}

    