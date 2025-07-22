
'use server';
import { getCurrentCompanyId, getAuthContext, getCurrentUser } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
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
    getReorderSuggestionsFromDB,
    createPurchaseOrdersInDb,
    getPurchaseOrdersFromDB,
    getInventoryLedgerFromDB,
    getChannelFeesFromDB,
    upsertChannelFeeInDb,
    createExportJobInDb,
    reconcileInventoryInDb,
    getSupplierPerformanceFromDB,
    getInventoryTurnoverFromDB,
    getMorningBriefing as getMorningBriefingFromChat,
} from '@/services/database';
import { SupplierFormData } from '@/types';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import type { Message, Conversation, ReorderSuggestion } from '@/types';
import { getServiceRoleClient } from '@/lib/supabase/admin';

export async function getProducts() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  const { items } = await getUnifiedInventoryFromDB(companyId, {});
  return items;
}

export async function getOrders() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  const { items } = await getSalesFromDB(companyId, { offset: 0, limit: 1000});
  return items;
}

export async function getCustomers() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  const { items } = await getCustomersFromDB(companyId, { offset: 0, limit: 1000});
  return items;
}

export async function getUnifiedInventory(params: { query: string, page: number, limit: number, status: string, sortBy: string, sortDirection: string }) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const offset = (params.page - 1) * params.limit;
    return getUnifiedInventoryFromDB(companyId, { ...params, offset });
}

export async function getInventoryAnalytics() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getInventoryAnalyticsFromDB(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return await getSuppliersDataFromDB(companyId);
}

export async function getDeadStockPageData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const settings = await getCompanySettings();
    const deadStockData = await getDeadStockReportFromDB(companyId);
    return {
        ...deadStockData,
        deadStockDays: settings.dead_stock_days
    };
}

export async function getSupplierById(id: string) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
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
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
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
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getTeamMembersFromDB(companyId);
}

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        
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
        const user = await getCurrentUser();
        const companyId = await getCurrentCompanyId();
        if (!companyId || !user) throw new Error('Unauthorized');

        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        if (user.id === memberId) throw new Error("You cannot remove yourself.");
        
        await removeTeamMemberFromDb(memberId, companyId);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const user = await getCurrentUser();
        const companyId = await getCurrentCompanyId();
        if (!companyId || !user) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
        if (user.id === memberId) throw new Error("You cannot change your own role.");
        
        await updateTeamMemberRoleInDb(memberId, companyId, newRole);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCompanySettings() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const settings = {
            dead_stock_days: Number(formData.get('dead_stock_days')),
            fast_moving_days: Number(formData.get('fast_moving_days')),
            overstock_multiplier: Number(formData.get('overstock_multiplier')),
            high_value_threshold: Number(formData.get('high_value_threshold')),
        }
        await updateSettingsInDb(companyId, settings);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSalesData(params: { query: string; page: number, limit: number }) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const offset = (params.page - 1) * params.limit;
    return getSalesFromDB(companyId, { ...params, offset });
}

export async function exportSales(params: { query: string }) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        const { items } = await getSalesFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSalesAnalytics() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getSalesAnalyticsFromDB(companyId);
}

export async function getCustomersData(params: { query: string; page: number, limit: number }) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const offset = (params.page - 1) * params.limit;
    return getCustomersFromDB(companyId, { ...params, offset });
}

export async function deleteCustomer(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
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
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        const { items } = await getCustomersFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCustomerAnalytics() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getCustomerAnalyticsFromDB(companyId);
}

export async function exportInventory(params: { query: string; status: string; sortBy: string; sortDirection: string; }) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getReorderReport() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getReorderSuggestionsFromDB(companyId);
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await validateCSRF(formData);
        const suggestions = JSON.parse(formData.get('suggestions') as string) as ReorderSuggestion[];
        const createdPoCount = await createPurchaseOrdersInDb(companyId, userId, suggestions);
        revalidatePath('/purchase-orders');
        return { success: true, createdPoCount };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const csv = Papa.unparse(suggestions);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getPurchaseOrders() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getPurchaseOrdersFromDB(companyId);
}

export async function getInventoryLedger(variantId: string) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getInventoryLedgerFromDB(companyId, variantId);
}

export async function getChannelFees() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getChannelFeesFromDB(companyId);
}

export async function upsertChannelFee(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const data = {
            channel_name: formData.get('channel_name') as string,
            fixed_fee: Number(formData.get('fixed_fee')),
            percentage_fee: Number(formData.get('percentage_fee'))
        }
        await upsertChannelFeeInDB(companyId, data);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function requestCompanyDataExport() {
    try {
        const { companyId, userId } = await getAuthContext();
        const job = await createExportJobInDb(companyId, userId);
        return { success: true, jobId: job.id };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function reconcileInventory(integrationId: string) {
    try {
        const { companyId, userId } = await getAuthContext();
        await reconcileInventoryInDb(companyId, integrationId, userId);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getDashboardData(dateRange: string) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getDashboardMetrics(companyId, dateRange);
}

export async function getMorningBriefing(dateRange: string) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const metrics = await getDashboardMetrics(companyId, dateRange);
    return getMorningBriefingFromChat({metrics});
}

export async function getSupplierPerformanceReportData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getSupplierPerformanceFromDB(companyId);
}

export async function getInventoryTurnoverReportData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
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

export async function handleUserMessage(params: { content: string, conversationId: string | null }): Promise<{ newMessage?: Message, conversationId?: string, error?: string }> {
  const { companyId, userId } = await getAuthContext();
  const { content, conversationId } = params;

  try {
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
