

'use server';
import { getAuthContext, getCurrentUser } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
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
    getDashboardMetrics,
    checkUserPermission,
    getReorderSuggestionsFromDB,
    getHistoricalSalesForSkus,
    refreshMaterializedViews,
    createAuditLogInDb as createAuditLogInDbService,
    adjustInventoryQuantityInDb,
    getAuditLogFromDB,
    logUserFeedbackInDb as logUserFeedbackInDbService,
    getAbcAnalysisFromDB,
    getSalesVelocityFromDB,
    getGrossMarginAnalysisFromDB,
    getFeedbackFromDB,
    deletePurchaseOrderFromDb,
    getSupplierPerformanceFromDB,
    getInventoryTurnoverFromDB
} from '@/services/database';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import type { SupplierFormData, Order, DashboardMetrics, ReorderSuggestion, PurchaseOrderFormData, ChannelFee, AuditLogEntry, FeedbackWithMessages, PurchaseOrderWithItems } from '@/types';
import { DashboardMetricsSchema, SupplierFormSchema } from '@/types';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { Message, Conversation } from '@/types';
import { z } from 'zod';
import { getMarkdownSuggestions } from '@/ai/flows/markdown-optimizer-flow';
import { getBundleSuggestions } from '@/ai/flows/suggest-bundles-flow';
import { findHiddenMoney } from '@/ai/flows/hidden-money-finder-flow';
import { getPromotionalImpactAnalysis } from '@/ai/flows/analytics-tools';
import { getPriceOptimizationSuggestions } from '@/ai/flows/price-optimization-flow';
import { getReorderSuggestions } from '@/ai/flows/reorder-tool';


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
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getUnifiedInventoryFromDB(companyId, { ...params, offset });
}

export async function getInventoryAnalytics() {
    const { companyId } = await getAuthContext();
    return getInventoryAnalyticsFromDB(companyId);
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
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getSalesFromDB(companyId, { ...params, offset });
}

export async function exportSales(params: { query: string }) {
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getSalesFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSalesAnalytics() {
    const { companyId } = await getAuthContext();
    return getSalesAnalyticsFromDB(companyId);
}

export async function getCustomersData(params: { query: string; page: number, limit: number }) {
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getCustomersFromDB(companyId, { ...params, offset });
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

export async function getCustomerAnalytics() {
    const { companyId } = await getAuthContext();
    return getCustomerAnalyticsFromDB(companyId);
}

export async function exportInventory(params: { query: string; status: string; sortBy: string; sortDirection: string; }) {
    try {
        const { companyId } = await getAuthContext();
        // Fetch all inventory items matching the filters, up to a reasonable limit.
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        
        // Customize the data for a cleaner CSV export
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
        }));
        
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        logError(e, { context: 'exportInventory failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getPurchaseOrders() {
    const { companyId } = await getAuthContext();
    return getPurchaseOrdersFromDB(companyId);
}

export async function getPurchaseOrderById(id: string) {
    const { companyId } = await getAuthContext();
    return getPurchaseOrderByIdFromDB(id, companyId);
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

const emptyMetrics: DashboardMetrics = {
    total_revenue: 0,
    revenue_change: 0,
    total_sales: 0,
    sales_change: 0,
    new_customers: 0,
    customers_change: 0,
    dead_stock_value: 0,
    sales_over_time: [],
    top_selling_products: [],
    inventory_summary: {
        total_value: 0,
        in_stock_value: 0,
        low_stock_value: 0,
        dead_stock_value: 0,
    },
};

export async function getDashboardData(dateRange: string): Promise<DashboardMetrics> {
    try {
        const { companyId } = await getAuthContext();
        const data = await getDashboardMetrics(companyId, dateRange);
        return DashboardMetricsSchema.parse(data);
    } catch (e) {
        logError(e, { context: 'getDashboardData failed, returning empty metrics' });
        return { ...emptyMetrics, error: getErrorMessage(e) } as DashboardMetrics;
    }
}

export async function getMorningBriefing(dateRange: string) {
    const { companyId } = await getAuthContext();
    const user = await getCurrentUser();
    const metrics = await getDashboardData(dateRange); // Use the safe version
    return generateMorningBriefing({ metrics, companyName: user?.user_metadata?.company_name });
}

export async function getSupplierPerformanceReportData() {
    const { companyId } = await getAuthContext();
    return getSupplierPerformanceFromDB(companyId);
}

export async function getInventoryTurnoverReportData() {
    const { companyId } = await getAuthContext();
    return getInventoryTurnoverFromDB(companyId, 90);
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
        .select('*')
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
    const { content, conversationId } = validatedInput;

    const supabase = getServiceRoleClient();
    let currentConversationId = conversationId;

    if (!currentConversationId) {
        const { data: newConversation, error } = await supabase.from('conversations').insert({
            user_id: userId,
            company_id: companyId,
            title: content.substring(0, 50)
        }).select().single();
        if(error) throw error;
        currentConversationId = newConversation.id;
    }

    await supabase.from('messages').insert({
        conversation_id: currentConversationId,
        company_id: companyId,
        role: 'user',
        content,
    });
    
    const { data: history } = await supabase.from('messages').select('*').eq('conversation_id', currentConversationId).order('created_at', { ascending: false }).limit(10);
    const reversedHistory = (history || []).reverse();

    const aiResponse = await universalChatFlow({
        companyId: companyId,
        conversationHistory: reversedHistory.map(m => ({ role: m.role, content: [{ text: m.content }] })) as any,
    });

    const { data: newMessage, error: messageError } = await supabase.from('messages').insert({
        conversation_id: currentConversationId,
        company_id: companyId,
        role: 'assistant',
        content: aiResponse.response,
        visualization: aiResponse.visualization,
        confidence: aiResponse.confidence,
        assumptions: aiResponse.assumptions,
        component: aiResponse.toolName,
        componentProps: { data: aiResponse.data }
    }).select().single();
    
    if (messageError) throw messageError;

    return { newMessage: newMessage as Message, conversationId: currentConversationId };

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

export async function getReorderReport() {
    const { companyId } = await getAuthContext();
    return getReorderSuggestions({ companyId });
}

export async function getDeadStockReport() {
    const { companyId } = await getAuthContext();
    return getDeadStockReportFromDB(companyId);
}

export async function getAdvancedAbcReport() {
    const { companyId } = await getAuthContext();
    return getAbcAnalysisFromDB(companyId);
}

export async function getAdvancedSalesVelocityReport() {
    const { companyId } = await getAuthContext();
    return getSalesVelocityFromDB(companyId, 90, 10);
}

export async function getAdvancedGrossMarginReport() {
    const { companyId } = await getAuthContext();
    return getGrossMarginAnalysisFromDB(companyId);
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
    throw new Error('Failed to retrieve audit log data.');
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
        throw new Error('Failed to retrieve feedback data.');
    }
}
