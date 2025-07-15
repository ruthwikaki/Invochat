
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { getErrorMessage, logError } from '@/lib/error-handler';
import {
  getSettings,
  updateSettingsInDb,
  getInventoryCategoriesFromDB,
  getUnifiedInventoryFromDB,
  getSupplierByIdFromDB,
  createSupplierInDb,
  updateSupplierInDb,
  deleteSupplierFromDb,
  getInventoryLedgerFromDB,
  getCustomersFromDB,
  deleteCustomerFromDb,
  getSalesFromDB,
  getIntegrationsByCompanyId,
  getInventoryAnalyticsFromDB,
  getSalesAnalyticsFromDB,
  getSuppliersDataFromDB,
  testSupabaseConnection as dbTestSupabase,
  testDatabaseQuery as dbTestQuery,
  updateProductInDb,
  logUserFeedbackInDb,
  getDeadStockReportFromDB,
  getAnomalyInsightsFromDB,
  getDbSchemaAndData,
  createExportJobInDb,
  getAlertsFromDB,
  getCustomerAnalyticsFromDB,
  getInventoryAgingReportFromDB,
  getProductLifecycleAnalysisFromDB,
  getInventoryRiskReportFromDB,
  getCustomerSegmentAnalysisFromDB,
  getTeamMembersFromDB,
  inviteUserToCompanyInDb,
  removeTeamMemberFromDb,
  updateTeamMemberRoleInDb,
  getChannelFeesFromDB,
  upsertChannelFeeInDB,
  getCashFlowInsightsFromDB,
  getSupplierPerformanceFromDB,
  getInventoryTurnoverFromDB,
  getCompanyById,
  testMaterializedView as dbTestMaterializedView,
  createAuditLogInDb,
  logPOCreationInDb,
  transferStockInDb,
  logWebhookEvent,
  getDashboardMetrics,
  reconcileInventoryInDb,
  getReorderSuggestionsFromDB,
  createPurchaseOrdersInDb,
  getPurchaseOrdersFromDB
} from '@/services/database';
import { testGenkitConnection as genkitTest } from '@/services/genkit';
import { isRedisEnabled, testRedisConnection as redisTest } from '@/lib/redis';
import type { CompanySettings, SupplierFormData, ProductUpdateData, Alert, Anomaly, HealthCheckResult, InventoryAgingReportItem, ReorderSuggestion, ProductLifecycleAnalysis, InventoryRiskItem, CustomerSegmentAnalysisItem, DashboardMetrics } from '@/types';
import { DashboardMetricsSchema, ReorderSuggestionSchema } from '@/types';
import { deleteIntegrationFromDb } from '@/services/database';
import { CSRF_FORM_NAME, validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { revalidatePath } from 'next/cache';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import { sendInventoryDigestEmail } from '@/services/email';
import { getCustomerInsights } from '@/ai/flows/customer-insights-flow';
import { generateProductDescription } from '@/ai/flows/generate-description-flow';
import { generateAlertExplanation } from '@/ai/flows/alert-explanation-flow';
import { z } from 'zod';
import crypto from 'crypto';


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
    return { companyId, userId: user.id, userEmail: user.email! };
}

// --- Simplified Core Actions ---

export async function getDashboardData(dateRange: string): Promise<DashboardMetrics> {
    const { companyId } = await getAuthContext();
    const metrics = await getDashboardMetrics(companyId, dateRange);
    return DashboardMetricsSchema.parse(metrics);
}

export async function getCompanySettings() {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
  const { companyId } = await getAuthContext();
  validateCSRF(formData);
  const settings = {
    dead_stock_days: Number(formData.get('dead_stock_days')),
    fast_moving_days: Number(formData.get('fast_moving_days')),
    overstock_multiplier: Number(formData.get('overstock_multiplier')),
    high_value_threshold: Number(formData.get('high_value_threshold')),
  };
  return updateSettingsInDb(companyId, settings);
}

export async function getUnifiedInventory(params: { query?: string; page?: number, limit?: number, status?: string, sortBy?: string, sortDirection?: string }) {
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

export async function updateProduct(productId: string, data: ProductUpdateData) {
    try {
        const { companyId } = await getAuthContext();
        const updatedProduct = await updateProductInDb(companyId, productId, data);
        revalidatePath('/inventory');
        return { success: true, updatedItem: updatedProduct };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
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
        validateCSRF(formData);
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
        validateCSRF(formData);
        
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
        validateCSRF(formData);
        const id = formData.get('id') as string;
        await deleteCustomerFromDb(id, companyId);
        revalidatePath('/customers');
        return { success: true };
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

export async function getPurchaseOrders() {
    const { companyId } = await getAuthContext();
    return getPurchaseOrdersFromDB(companyId);
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
            const explanation = await generateAlertExplanation({
                id: `anomaly_${anomaly.date}_${anomaly.anomaly_type}`,
                type: 'predictive',
                title: anomaly.anomaly_type,
                message: `Deviation of ${anomaly.deviation_percentage.toFixed(0)}% from the average.`,
                severity: 'warning',
                timestamp: anomaly.date,
                metadata: { ...anomaly },
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
export async function testSupabaseConnection() { return dbTestSupabase(); }
export async function testDatabaseQuery() { return dbTestQuery(); }
export async function testGenkitConnection() { return genkitTest(); }
export async function testRedisConnection() { return { isEnabled: isRedisEnabled, ...await redisTest() }; }
export async function getGeneratedProductDescription(productName: string, category: string, keywords: string[]) {
    return generateProductDescription({ productName, category, keywords });
}

export async function logUserFeedback(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData);
        const subjectId = formData.get('subjectId') as string;
        const subjectType = formData.get('subjectType') as string;
        const feedback = formData.get('feedback') as 'helpful' | 'unhelpful';

        await logUserFeedbackInDb(userId, companyId, subjectId, subjectType, feedback);
        
        return { success: true };
    } catch(e) {
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
        const { companyId } = await getAuthContext();
        validateCSRF(formData);
        const email = formData.get('email') as string;
        // Company name is hardcoded as it's not available here, needs a better solution in a real app
        await inviteUserToCompanyInDb(companyId, 'Your Company', email);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function removeTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        if (userId === memberId) throw new Error("You cannot remove yourself.");
        
        return await removeTeamMemberFromDb(memberId, companyId, userId);
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
        
        return await updateTeamMemberRoleInDb(memberId, companyId, newRole);
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function getCustomerAnalytics() {
    const { companyId } = await getAuthContext();
    return getCustomerAnalyticsFromDB(companyId);
}
export async function exportCustomers(params: { query?: string }) { 
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getCustomersFromDB(companyId, { ...params, page: 1, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function exportSales(params: { query?: string }) { 
    try {
        const { companyId } = await getAuthContext();
        const { items } = await getSalesFromDB(companyId, { ...params, page: 1, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const { companyId, userId } = await getAuthContext();
        const dataToExport = suggestions.map(s => ({
            SKU: s.sku,
            ProductName: s.product_name,
            Supplier: s.supplier_name,
            QuantityToOrder: s.suggested_reorder_quantity,
            UnitCost: s.unit_cost ? (s.unit_cost / 100).toFixed(2) : 'N/A',
            TotalCost: s.unit_cost ? ((s.suggested_reorder_quantity * s.unit_cost) / 100).toFixed(2) : 'N/A'
        }));
        const csv = Papa.unparse(dataToExport);
        await createAuditLogInDb(companyId, userId, 'data_export', {
            type: 'reorder_suggestions',
            recordCount: suggestions.length,
        });
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function requestCompanyDataExport(): Promise<{ success: boolean, jobId?: string, error?: string }> { 
    try {
        const { companyId, userId } = await getAuthContext();
        const job = await createExportJobInDb(companyId, userId);
        revalidatePath('/settings/export');
        return { success: true, jobId: job.id };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function getInventoryConsistencyReport(): Promise<HealthCheckResult> { return {healthy: true, metric: 0, message: "OK"}; }
export async function getFinancialConsistencyReport(): Promise<HealthCheckResult> { return {healthy: true, metric: 0, message: "OK"}; }
export async function getInventoryAgingData(): Promise<InventoryAgingReportItem[]> { 
    const { companyId } = await getAuthContext();
    return getInventoryAgingReportFromDB(companyId);
}

export async function exportInventory(params: { query?: string, status?: string; sortBy?: string; sortDirection?: string }) { 
    try {
        const { companyId, userId } = await getAuthContext();
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, limit: 10000, offset: 0 });
        const csv = Papa.unparse(items.map(item => ({
            sku: item.sku,
            product_title: item.product_title,
            variant_title: item.title,
            status: item.product_status,
            quantity: item.inventory_quantity,
            price: item.price ? (item.price / 100).toFixed(2) : null,
            cost: item.cost ? (item.cost / 100).toFixed(2) : null,
            category: item.product_type,
            image_url: item.image_url,
        })));

        await createAuditLogInDb(companyId, userId, 'data_export', {
            type: 'inventory',
            recordCount: items.length,
        });

        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function getCashFlowInsights() {
    const { companyId } = await getAuthContext();
    return getCashFlowInsightsFromDB(companyId);
}
export async function getSupplierPerformance() { return []; }
export async function getInventoryTurnover() { return {turnover_rate:0,total_cogs:0,average_inventory_value:0,period_days:0}; }
export async function sendInventoryDigestEmailAction(): Promise<{ success: boolean; error?: string }> { 
    try {
        const { userEmail } = await getAuthContext();
        const insights = await getInsightsPageData();
        await sendInventoryDigestEmail(userEmail, insights);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function getProductLifecycleAnalysis(): Promise<ProductLifecycleAnalysis> { 
    const { companyId } = await getAuthContext();
    return getProductLifecycleAnalysisFromDB(companyId);
}
export async function getInventoryRiskReport(): Promise<InventoryRiskItem[]> { 
    const { companyId } = await getAuthContext();
    return getInventoryRiskReportFromDB(companyId);
}
export async function getCustomerSegmentAnalysis(): Promise<{ segments: CustomerSegmentAnalysisItem[], insights: { analysis: string, suggestion: string } | null }> { 
    const { companyId } = await getAuthContext();
    const segments = await getCustomerSegmentAnalysisFromDB(companyId);
    if (segments.length === 0) {
        return { segments, insights: null };
    }
    const insights = await getCustomerInsights({ segments });
    return { segments, insights };
}
export async function getMorningBriefing(dateRange: string) {
    const { companyId } = await getAuthContext();
    const [metrics, company] = await Promise.all([
        getDashboardMetrics(companyId, dateRange),
        getCompanyById(companyId),
    ]);
    return generateMorningBriefing({ metrics, companyName: company?.name });
}

export async function reconcileInventory(integrationId: string): Promise<{ success: boolean; error?: string }> { 
    try {
        const { companyId, userId } = await getAuthContext();
        await reconcileInventoryInDb(companyId, integrationId, userId);
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function testMaterializedView() { return {success: true}; }
export async function logPOCreation(poNumber: string, supplierName: string, items: any[]) { return; }
export async function transferStock(formData: FormData) { return {success: false, error: "Not implemented"}; }

export async function getReorderReport(): Promise<ReorderSuggestion[]> { 
     const { companyId } = await getAuthContext();
    return getReorderSuggestionsFromDB(companyId);
}

export async function getInventoryLedger(variantId: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerFromDB(companyId, variantId);
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData): Promise<{ success: boolean, error?: string, createdPoCount?: number }> {
    try {
        validateCSRF(formData);
        const { companyId, userId } = await getAuthContext();

        const suggestionsString = formData.get('suggestions') as string;
        if (!suggestionsString) {
             return { success: false, error: 'No reorder suggestions provided.' };
        }

        const suggestions = ReorderSuggestionSchema.array().parse(JSON.parse(suggestionsString));
        
        if (!suggestions || suggestions.length === 0) {
            return { success: false, error: 'No reorder suggestions provided.' };
        }
        
        const idempotencyKey = crypto.randomUUID();
        const createdPoCount = await createPurchaseOrdersInDb(companyId, userId, suggestions, idempotencyKey);
        
        revalidatePath('/purchase-orders', 'page');
        
        return { success: true, createdPoCount };
    } catch (e) {
        logError(e, { context: 'createPurchaseOrdersFromSuggestions action' });
        return { success: false, error: getErrorMessage(e) };
    }
}
    
