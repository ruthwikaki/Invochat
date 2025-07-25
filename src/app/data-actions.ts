
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
    createPurchaseOrdersInDb,
    getPurchaseOrdersFromDB,
    getInventoryLedgerFromDB,
    getChannelFeesFromDB,
    upsertChannelFeeInDb,
    createExportJobInDb,
    reconcileInventoryInDb,
    getSupplierPerformanceFromDB,
    getInventoryTurnoverFromDB,
    getDashboardMetrics,
    checkUserPermission,
    getReorderSuggestionsFromDB,
    getHistoricalSalesForSkus,
    getQueryPatternsForCompany,
    saveSuccessfulQuery,
    getDatabaseSchemaAndData,
    refreshMaterializedViews,
    createAuditLogInDb,
    logUserFeedbackInDb as logUserFeedback,
} from '@/services/database';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import type { SupplierFormData } from '@/types';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { Message, Conversation, ReorderSuggestion } from '@/types';
import { z } from 'zod';

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

export async function getDeadStockPageData() {
    const { companyId } = await getAuthContext();
    const settings = await getSettings(companyId);
    const deadStockData = await getDeadStockReportFromDB(companyId);
    return {
        ...deadStockData,
        deadStockDays: settings.dead_stock_days
    };
}

export async function getSupplierById(id: string) {
    const { companyId } = await getAuthContext();
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData) {
    try {
        const { companyId } = await getAuthContext();
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData) {
    try {
        const { companyId } = await getAuthContext();
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
        const { companyId } = await getAuthContext();
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
        await checkUserPermission(userId, 'Admin');
        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        if (userId === memberId) throw new Error("You cannot remove yourself.");
        
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
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
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
        await createAuditLogInDb(companyId, userId, 'company_settings_updated', settings);
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

export async function getReorderReport() {
    const { companyId } = await getAuthContext();
    return getReorderSuggestionsFromDB(companyId);
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const suggestions = JSON.parse(formData.get('suggestions') as string) as ReorderSuggestion[];
        const result = await createPurchaseOrdersInDb(companyId, userId, suggestions);
        
        await createAuditLogInDb(companyId, userId, 'ai_purchase_order_created', {
            createdPoCount: result,
            totalSuggestions: suggestions.length,
            // Log a sample of SKUs for auditability without logging everything
            sampleSkus: suggestions.slice(0, 5).map(s => s.sku),
        });

        revalidatePath('/purchase-orders');
        revalidatePath('/analytics/reordering');
        return { success: true, createdPoCount: result };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const dataToExport = suggestions.map(s => ({
            sku: s.sku,
            product_name: s.product_name,
            supplier_name: s.supplier_name,
            current_quantity: s.current_quantity,
            suggested_reorder_quantity: s.suggested_reorder_quantity,
            unit_cost: s.unit_cost !== null && s.unit_cost !== undefined ? (s.unit_cost / 100).toFixed(2) : '',
            total_cost: s.unit_cost !== null && s.unit_cost !== undefined ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : '',
            adjustment_reason: s.adjustment_reason,
            confidence: s.confidence,
        }));
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        logError(e, { context: 'exportReorderSuggestions failed' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getPurchaseOrders() {
    const { companyId } = await getAuthContext();
    return getPurchaseOrdersFromDB(companyId);
}

export async function getInventoryLedger(variantId: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerFromDB(companyId, variantId);
}

export async function getChannelFees() {
    const { companyId } = await getAuthContext();
    return getChannelFeesFromDB(companyId);
}

export async function upsertChannelFee(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        await validateCSRF(formData);
        const data = {
            channel_name: formData.get('channel_name') as string,
            fixed_fee: Number(formData.get('fixed_fee')),
            percentage_fee: Number(formData.get('percentage_fee'))
        }
        await upsertChannelFeeInDb(companyId, data);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function requestCompanyDataExport() {
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

export async function getDashboardData(dateRange: string) {
    const { companyId } = await getAuthContext();
    return getDashboardMetrics(companyId, dateRange);
}

export async function getMorningBriefing(dateRange: string) {
    const { companyId } = await getAuthContext();
    const user = await getCurrentUser();
    const metrics = await getDashboardMetrics(companyId, dateRange);
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

export async function logUserFeedbackInDb(params: { subjectId: string, subjectType: string, feedback: 'helpful' | 'unhelpful' }): Promise<{ success: boolean, error?: string}> {
    try {
        const { companyId, userId } = await getAuthContext();
        await logUserFeedback(userId, companyId, params.subjectId, params.subjectType, params.feedback);
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

    