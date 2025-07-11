

'use server';

import type { Message } from '@/types';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';
import {
  getDashboardMetrics,
  getDeadStockPageData,
  getAlertsFromDB,
  getDbSchemaAndData,
  getSettings,
  updateSettingsInDb,
  getAnomalyInsightsFromDB,
  getInventoryCategoriesFromDB,
  getUnifiedInventoryFromDB,
  getTeamMembersFromDB,
  inviteUserToCompanyInDb,
  removeTeamMemberFromDb,
  updateTeamMemberRoleInDb,
  getReorderSuggestionsFromDB,
  createPurchaseOrdersFromSuggestionsInDb,
  getPurchaseOrdersFromDB,
  getPurchaseOrderByIdFromDB,
  updatePurchaseOrderInDb,
  deletePurchaseOrderFromDb,
  receivePurchaseOrderItemsInDB,
  getChannelFeesFromDB,
  upsertChannelFeeInDB,
  getLocationsFromDB,
  getLocationByIdFromDB,
  createLocationInDB,
  updateLocationInDB,
  deleteLocationFromDb,
  getSupplierByIdFromDB,
  createSupplierInDb,
  updateSupplierInDb,
  deleteSupplierFromDb,
  softDeleteInventoryItemsFromDb,
  updateInventoryItemInDb,
  getInventoryLedgerForSkuFromDB,
  getCustomersFromDB,
  getCustomerAnalyticsFromDB,
  deleteCustomerFromDb,
  searchProductsForSaleInDB,
  recordSaleInDB,
  getSalesFromDB,
  createExportJobInDb,
  refreshMaterializedViews,
  getIntegrationsByCompanyId,
  getInventoryAnalyticsFromDB,
  getSalesAnalyticsFromDB,
  getSuppliersDataFromDB,
  testSupabaseConnection as dbTestSupabase,
  testDatabaseQuery as dbTestQuery,
  testMaterializedView as dbTestMView,
  getBusinessProfile,
  healthCheckInventoryConsistency,
  healthCheckFinancialConsistency,
  createAuditLogInDb,
  updateProductInDb,
  approvePurchaseOrderInDb,
  transferInventoryInDb,
  reconcileInventoryInDb,
  getInventoryAgingReportFromDB,
  getFinancialImpactOfPoFromDB as dbGetFinancialImpact,
  logUserFeedbackInDb,
  getSalesVelocityFromDB,
  getDemandForecastFromDB,
  getAbcAnalysisFromDB,
  getGrossMarginAnalysisFromDB,
  getNetMarginByChannelFromDB,
  getMarginTrendsFromDB,
  getHistoricalSalesForSkus,
  getSupplierPerformanceFromDB,
  getInventoryTurnoverFromDB
} from '@/services/database';
import { testGenkitConnection as genkitTest } from '@/services/genkit';
import { isRedisEnabled, testRedisConnection as redisTest } from '@/lib/redis';
import {
    generateAnomalyExplanation,
} from '@/ai/flows/anomaly-explanation-flow';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import type { Alert, Anomaly, CompanySettings, InventoryUpdateData, LocationFormData, PurchaseOrder, PurchaseOrderCreateInput, PurchaseOrderUpdateInput, ReorderSuggestion, ReceiveItemsFormInput, SupplierFormData, SaleCreateInput, ProductUpdateData, InventoryAgingReportItem, HealthCheckResult } from '@/types';
import { sendPurchaseOrderEmail } from '@/services/email';
import { deleteIntegrationFromDb } from '@/services/database';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME, validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { ai } from '@/ai/genkit';
import { createPurchaseOrderInDb } from '@/services/database';

async function getAuthContext() {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('User not authenticated.');
    const companyId = user.app_metadata?.company_id;
    if (!companyId) throw new Error('Company ID not found for user.');
    return { companyId, userId: user.id };
}

// --- Simplified Core Actions ---

export async function getDashboardData(dateRange: string) {
    const { companyId } = await getAuthContext();
    return getDashboardMetrics(companyId, dateRange);
}

export async function getCompanySettings() {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
  const { companyId } = await getAuthContext();
  validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
  const settings = {
    dead_stock_days: Number(formData.get('dead_stock_days')),
    fast_moving_days: Number(formData.get('fast_moving_days')),
    overstock_multiplier: Number(formData.get('overstock_multiplier')),
    high_value_threshold: Number(formData.get('high_value_threshold')),
  };
  return updateSettingsInDb(companyId, settings);
}

export async function getUnifiedInventory(params: { query?: string; category?: string; supplier?: string, page?: number, limit?: number }) {
    const { companyId } = await getAuthContext();
    return getUnifiedInventoryFromDB(companyId, { ...params, offset: ((params.page || 1) - 1) * (params.limit || 50) });
}

export async function getInventoryAnalytics() {
    const { companyId } = await getAuthContext();
    return getInventoryAnalyticsFromDB(companyId);
}

export async function getInventoryCategories() {
    const { companyId } = await getAuthContext();
    return getInventoryCategoriesFromDB(companyId);
}

export async function deleteInventoryItems(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        const productIdsString = formData.get('productIds') as string;
        if (!productIdsString) throw new Error('No Product IDs provided for deletion.');
        
        const productIds = JSON.parse(productIdsString);
        await softDeleteInventoryItemsFromDb(companyId, productIds, userId);
        
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateProduct(productId: string, data: ProductUpdateData) {
    try {
        const { companyId, userId } = await getAuthContext();
        const updatedProduct = await updateProductInDb(companyId, productId, data);
        revalidatePath('/inventory');
        return { success: true, updatedItem: updatedProduct };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function getInventoryLedger(productId: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerForSkuFromDB(companyId, productId);
}

export async function getSuppliersData() {
    const { companyId } = await getAuthContext();
    return getSuppliersDataFromDB(companyId);
}

export async function getSupplierById(id: string) {
    const { companyId } = await getAuthContext();
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData) {
    try {
        const { companyId } = await getAuthContext();
        await createSupplierInDb(companyId, data);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData) {
    try {
        const { companyId } = await getAuthContext();
        await updateSupplierInDb(id, companyId, data);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
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
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        
        const { companyId } = await getAuthContext();
        const id = formData.get('integrationId') as string;
        await deleteIntegrationFromDb(id, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCustomersData(params: { query?: string, page: number }) {
    const { companyId } = await getAuthContext();
    const limit = 25;
    const offset = (params.page - 1) * limit;
    return getCustomersFromDB(companyId, { ...params, limit, offset });
}

export async function deleteCustomer(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        const id = formData.get('id') as string;
        await deleteCustomerFromDb(id, companyId);
        revalidatePath('/customers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function searchProductsForSale(query: string) {
    const { companyId } = await getAuthContext();
    return searchProductsForSaleInDB(companyId, query);
}

export async function recordSale(formData: FormData): Promise<{ success: boolean, sale?: any, error?: string }> {
    try {
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);

        const { companyId, userId } = await getAuthContext();
        const saleDataString = formData.get('saleData') as string;
        const saleData: SaleCreateInput = JSON.parse(saleDataString);
        
        const sale = await recordSaleInDB(companyId, userId, saleData);
        revalidatePath('/sales');
        return { success: true, sale };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSales(params: { query?: string, page: number, limit: number }) {
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getSalesFromDB(companyId, { ...params, offset });
}

export async function getSalesAnalytics() {
    const { companyId } = await getAuthContext();
    return getSalesAnalyticsFromDB(companyId);
}

export async function getCustomerAnalytics() {
    const { companyId } = await getAuthContext();
    return getCustomerAnalyticsFromDB(companyId);
}

// --- Report Actions ---

export async function getDeadStockData() {
    const { companyId } = await getAuthContext();
    return getDeadStockReportFromDB(companyId);
}

export async function getReorderReport(): Promise<ReorderSuggestion[]> {
    const { companyId } = await getAuthContext();
    return getReorderSuggestionsFromDB(companyId);
}

export async function getInventoryHealthScore() {
    const { companyId } = await getAuthContext();
    return getInventoryHealthScoreFromDB(companyId);
}

export async function findProfitLeaks() {
    const { companyId } = await getAuthContext();
    return findProfitLeaksFromDB(companyId);
}

export async function getAbcAnalysis() {
    const { companyId } = await getAuthContext();
    return getAbcAnalysisFromDB(companyId);
}

export async function getInsightsPageData() {
    const { companyId } = await getAuthContext();
    const [rawAnomalies, topDeadStockData, topLowStock] = await Promise.all([
        getAnomalyInsightsFromDB(companyId),
        getDeadStockReportFromDB(companyId),
        getAlertsFromDB(companyId),
    ]);

    const explainedAnomalies = await Promise.all(
        rawAnomalies.map(async (anomaly) => {
            const date = new Date(anomaly.date);
            const explanation = await generateAnomalyExplanation({
                anomaly,
                dateContext: {
                    dayOfWeek: date.toLocaleDateString('en-US', { weekday: 'long' }),
                    month: date.toLocaleDateString('en-US', { month: 'long' }),
                    season: 'Summer', // This is a placeholder; a real app might use a date library for this
                    knownHoliday: undefined, // Placeholder; would need a holiday calendar
                },
            });
            return { ...anomaly, ...explanation, id: `anomaly_${anomaly.date}_${anomaly.anomaly_type}` };
        })
    );
    
    const summary = await generateInsightsSummary({
        anomalies: explainedAnomalies,
        lowStockCount: topLowStock.filter(a => a.type === 'low_stock').length,
        deadStockCount: topDeadStockData.deadStockItems.length,
    });

    return {
        summary,
        anomalies: explainedAnomalies,
        topDeadStock: topDeadStockData.deadStockItems.slice(0, 3),
        topLowStock: topLowStock.filter(a => a.type === 'low_stock').slice(0, 3),
    };
}


// --- System & Test Actions ---

export async function testSupabaseConnection(): Promise<{ isConfigured: boolean; success: boolean; user: any; error?: Error; }> {
    return dbTestSupabase();
}

export async function testDatabaseQuery(): Promise<{ success: boolean; error?: string; }> {
    return dbTestQuery();
}

export async function testGenkitConnection(): Promise<{ isConfigured: boolean; success: boolean; error?: string; }> {
    return genkitTest();
}

export async function testRedisConnection(): Promise<{ isEnabled: boolean; success: boolean; error?: string; }> {
    return {
        isEnabled: isRedisEnabled,
        ...await redisTest()
    };
}

export async function logUserFeedback(formData: FormData): Promise<{ success: boolean; error?: string }> {
  try {
    const { companyId, userId } = await getAuthContext();
    const subjectId = formData.get('subjectId') as string;
    const subjectType = formData.get('subjectType') as string;
    const feedback = formData.get('feedback') as 'helpful' | 'unhelpful';

    if (!subjectId || !subjectType || !feedback) {
      throw new Error('Missing required feedback data.');
    }
    
    await logUserFeedbackInDb(userId, companyId, subjectId, subjectType, feedback);
    
    return { success: true };
  } catch(e) {
    logError(e, { context: 'logUserFeedback action failed' });
    return { success: false, error: getErrorMessage(e) };
  }
}


export async function getAlertsData(): Promise<Alert[]> {
    const { companyId } = await getAuthContext();
    return getAlertsFromDB(companyId);
}

export async function getDatabaseSchemaAndData() {
    const { companyId } = await getAuthContext();
    return getDbSchemaAndData(companyId);
}

export async function getTeamMembers() {
    const { companyId } = await getAuthContext();
    return getTeamMembersFromDB(companyId);
}

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        const email = formData.get('email') as string;
        await inviteUserToCompanyInDb(companyId, 'Your Company', email);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function removeTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        const memberId = formData.get('memberId') as string;
        if (userId === memberId) throw new Error("You cannot remove yourself.");
        
        return await removeTeamMemberFromDb(memberId, companyId, userId);
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
        
        return await updateTeamMemberRoleInDb(memberId, companyId, newRole);
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getChannelFees() {
    const { companyId } = await getAuthContext();
    return getChannelFeesFromDB(companyId);
}

export async function upsertChannelFee(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        validateCSRF(formData, cookies().get(CSRF_COOKIE_NAME)?.value);
        
        const percentageFee = parseFloat(formData.get('percentage_fee') as string);
        if (isNaN(percentageFee) || percentageFee < 0 || percentageFee > 1) {
            throw new Error('Percentage fee must be a decimal between 0 and 1 (e.g., 0.029 for 2.9%).');
        }

        const feeData = {
            channel_name: formData.get('channel_name') as string,
            percentage_fee: percentageFee,
            fixed_fee: Math.round(parseFloat(formData.get('fixed_fee') as string) * 100),
        };
        await upsertChannelFeeInDB(companyId, feeData);
        revalidatePath('/settings');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function exportCustomers(params: { query?: string }) {
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getCustomersFromDB(companyId, { ...params, limit: 10000, offset: 0 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function exportSales(params: { query?: string }) {
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getSalesFromDB(companyId, { ...params, limit: 10000, page: 1 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const dataToExport = suggestions.map(s => ({
            SKU: s.sku,
            ProductName: s.product_name,
            Supplier: s.supplier_name,
            QuantityToOrder: s.suggested_reorder_quantity,
            UnitCost: s.unit_cost ? (s.unit_cost / 100).toFixed(2) : 'N/A',
            TotalCost: s.unit_cost ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : 'N/A'
        }));
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function requestCompanyDataExport(): Promise<{ success: boolean, jobId?: string, error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        const job = await createExportJobInDb(companyId, userId);
        logger.info(`[Export] Job ${job.id} created for company ${companyId}.`);
        return { success: true, jobId: job.id };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function getInventoryConsistencyReport(): Promise<HealthCheckResult> {
    const { companyId } = await getAuthContext();
    return healthCheckInventoryConsistency(companyId);
}

export async function getFinancialConsistencyReport(): Promise<HealthCheckResult> {
    const { companyId } = await getAuthContext();
    return healthCheckFinancialConsistency(companyId);
}

export async function getInventoryAgingData(): Promise<InventoryAgingReportItem[]> {
    const { companyId } = await getAuthContext();
    return getInventoryAgingReportFromDB(companyId);
}

export async function exportInventory(params: { query?: string; category?: string; supplier?: string }) {
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, limit: 10000, offset: 0 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCashFlowInsights() {
    const { companyId } = await getAuthContext();
    return getCashFlowInsightsFromDB(companyId);
}

export async function getSupplierPerformance() {
    const { companyId } = await getAuthContext();
    return getSupplierPerformanceFromDB(companyId);
}

export async function getInventoryTurnover() {
    const { companyId } = await getAuthContext();
    const settings = await getSettings(companyId);
    return getInventoryTurnoverFromDB(companyId, settings.fast_moving_days);
}

export async function handleUserMessage({ content, conversationId, source = 'chat_page' }: { content: string, conversationId: string | null, source?: string }) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'ai_chat', config.ratelimit.ai, 60);
        if (limited) {
            return { error: 'You have reached the request limit. Please try again in a minute.' };
        }

        const companyId = await getAuthContext();
        
        let currentConversationId = conversationId;
        if (!currentConversationId) {
            const newTitle = content.length > 50 ? `${content.substring(0, 50)}...` : content;
            currentConversationId = await saveConversation(companyId, newTitle);
        }

        const userMessageToSave = {
            conversation_id: currentConversationId,
            company_id: companyId,
            role: 'user' as const,
            content: content,
        };
        await saveMessage(userMessageToSave);

        // Fetch recent messages for history
        const cookieStore = cookies();
        const supabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            {
              cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: historyData, error: historyError } = await supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', currentConversationId)
            .order('created_at', { ascending: false })
            .limit(config.ai.historyLimit);

        if (historyError) {
            logError(historyError, { context: 'Failed to fetch conversation history' });
        }
        const conversationHistory = (historyData || []).map(m => ({
            role: m.role as 'user' | 'assistant' | 'tool',
            content: [{ text: m.content }]
        })).reverse();


        const response = await universalChatFlow({ companyId, conversationHistory });
        
        let component = null;
        let componentProps = {};

        if (response.toolName === 'getDeadStockReport') {
            component = 'deadStockTable';
            componentProps = { data: response.data };
        }
        if (response.toolName === 'getReorderSuggestions') {
            component = 'reorderList';
            componentProps = { items: response.data };
        }
        if (response.toolName === 'getSupplierPerformanceReport') {
            component = 'supplierPerformanceTable';
            componentProps = { data: response.data };
        }
         if (response.toolName === 'createPurchaseOrdersFromSuggestions') {
            component = 'confirmation';
            componentProps = { ...response.data };
        }

        const newMessage: Message = {
            id: `ai_${Date.now()}`,
            conversation_id: currentConversationId,
            company_id: companyId,
            role: 'assistant',
            content: response.response,
            visualization: response.visualization,
            confidence: response.confidence,
            assumptions: response.assumptions,
            created_at: new Date().toISOString(),
            component,
            componentProps
        };

        await saveMessage({ ...newMessage, id: undefined, created_at: undefined });
        
        return { newMessage, conversationId: currentConversationId };

    } catch(e) {
        logError(e, { context: `handleUserMessage action for conversation ${conversationId}` });
        return { error: getErrorMessage(e) };
    }
}
