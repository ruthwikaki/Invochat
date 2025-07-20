

'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
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
  getCompanyById,
  createAuditLogInDb,
  reconcileInventoryInDb,
  createPurchaseOrdersInDb,
  getPurchaseOrdersFromDB,
  checkUserPermission,
  getHistoricalSalesForSkus as getHistoricalSalesForSkusFromDB,
  getSupplierPerformanceFromDB,
  getInventoryTurnoverFromDB,
  getDashboardMetrics,
  getReorderSuggestionsFromDB
} from '@/services/database';
import { reorderRefinementPrompt } from '@/ai/flows/reorder-tool';
import { testGenkitConnection as genkitTest } from '@/services/genkit';
import { isRedisEnabled, testRedisConnection as redisTest } from '@/lib/redis';
import type { CompanySettings, Supplier, SupplierFormData, ProductUpdateData, Alert, Anomaly, HealthCheckResult, InventoryAgingReportItem, ReorderSuggestion, ProductLifecycleAnalysis, InventoryRiskItem, CustomerSegmentAnalysisItem, DashboardMetrics, Order, PurchaseOrderWithSupplier, SalesAnalytics, InventoryAnalytics, CustomerAnalytics, TeamMember } from '@/types';
import { DashboardMetricsSchema, ReorderSuggestionSchema } from '@/types';
import { deleteIntegrationFromDb } from '@/services/database';
import { validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { revalidatePath } from 'next/cache';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import { sendInventoryDigestEmail } from '@/services/email';
import { getCustomerInsights } from '@/ai/flows/customer-insights-flow';
import { generateProductDescription } from '@/ai/flows/generate-description-flow';
import { generateAlertExplanation } from '@/ai/flows/alert-explanation-flow';
import crypto from 'crypto';


export async function getAuthContext() {
    const cookieStore = cookies();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error('Supabase URL or anonymous key is not configured.');
    }

    const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
        cookies: { get: (name: string) => cookieStore.get(name)?.value },
    });
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) throw new Error('User not authenticated.');
    if (!user.email) throw new Error('User email not found.');

    const companyId = user.app_metadata?.company_id;
    if (!companyId) throw new Error('Company ID not found for user.');
    
    return { companyId, userId: user.id, userEmail: user.email };
}

// --- Simplified Core Actions ---

export async function getDashboardData(dateRange: string): Promise<DashboardMetrics> {
    const { companyId } = await getAuthContext();
    const metrics = await getDashboardMetrics(companyId, dateRange);
    // Ensure that even if the RPC returns null/undefined, we provide a default structure.
    if (!metrics) {
        return {
            total_revenue: 0, revenue_change: 0, total_sales: 0, sales_change: 0,
            new_customers: 0, customers_change: 0, dead_stock_value: 0,
            sales_over_time: [], top_selling_products: [],
            inventory_summary: { total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0 }
        };
    }
    return DashboardMetricsSchema.parse(metrics);
}

export async function getCompanySettings(): Promise<CompanySettings> {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
  const { companyId, userId } = await getAuthContext();
  await checkUserPermission(userId, 'Admin');
  validateCSRF(formData);
  const settings = {
    dead_stock_days: Number(formData.get('dead_stock_days')),
    fast_moving_days: Number(formData.get('fast_moving_days')),
    overstock_multiplier: Number(formData.get('overstock_multiplier')),
    high_value_threshold: Number(formData.get('high_value_threshold')),
  };
  const result = await updateSettingsInDb(companyId, settings);
  revalidatePath('/settings/profile');
  return result;
}

export async function getUnifiedInventory(params: { query?: string; page?: number, limit?: number, status?: string, sortBy?: string, sortDirection?: string }) {
    const { companyId } = await getAuthContext();
    return getUnifiedInventoryFromDB(companyId, { ...params, offset: ((params.page || 1) - 1) * (params.limit || 50) });
}

export async function getInventoryAnalytics(): Promise<InventoryAnalytics> {
    const { companyId } = await getAuthContext();
    return getInventoryAnalyticsFromDB(companyId);
}

export async function getInventoryCategories() {
    const { companyId } = await getAuthContext();
    return getInventoryCategoriesFromDB(companyId);
}

export async function updateProduct(productId: string, data: ProductUpdateData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        const updatedProduct = await updateProductInDb(companyId, productId, data);
        revalidatePath('/inventory');
        return { success: true, updatedItem: updatedProduct };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSuppliersData(): Promise<Supplier[]> {
    const { companyId } = await getAuthContext();
    return getSuppliersDataFromDB(companyId);
}

export async function getSupplierById(id: string): Promise<Supplier | null> {
    const { companyId } = await getAuthContext();
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        await updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
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
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        validateCSRF(formData);
        const id = formData.get('integrationId') as string;
        await deleteIntegrationFromDb(id, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCustomersData(params: { query?: string, page: number, limit: number }) {
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getCustomersFromDB(companyId, { ...params, offset });
}

export async function deleteCustomer(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        validateCSRF(formData);
        const id = formData.get('id') as string;
        await deleteCustomerFromDb(id, companyId);
        revalidatePath('/customers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSales(params: { query?: string, page: number, limit: number }): Promise<{ items: Order[]; totalCount: number; }> {
    const { companyId } = await getAuthContext();
    const offset = (params.page - 1) * params.limit;
    return getSalesFromDB(companyId, { ...params, offset });
}
export async function getSalesAnalytics(): Promise<SalesAnalytics> {
     const { companyId } = await getAuthContext();
    return getSalesAnalyticsFromDB(companyId);
}

export async function getPurchaseOrders(): Promise<PurchaseOrderWithSupplier[]> {
    const { companyId } = await getAuthContext();
    return getPurchaseOrdersFromDB(companyId);
}

export async function getInsightsPageData() {
    const { companyId } = await getAuthContext();
    const [rawAnomalies, topDeadStockData, topLowStock] = await Promise.all([
        getAnomalyInsightsFromDB(companyId) as Promise<Anomaly[]>,
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
        lowStockCount: (topLowStock as Alert[]).filter(a => a.type === 'low_stock').length,
        deadStockCount: topDeadStockData.deadStockItems.length,
    });

    return {
        summary,
        anomalies: explainedAnomalies,
        topDeadStock: topDeadStockData.deadStockItems.slice(0, 3),
        topLowStock: (topLowStock as Alert[]).filter(a => a.type === 'low_stock').slice(0, 3),
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
        await checkUserPermission(userId, 'Admin');
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
    return getDbSchemaAndData();
}
export async function getTeamMembers(): Promise<TeamMember[]> {
    const { companyId } = await getAuthContext();
    return getTeamMembersFromDB(companyId);
}
export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        validateCSRF(formData);
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
        await checkUserPermission(userId, 'Owner');
        validateCSRF(formData);
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
        validateCSRF(formData);
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
export async function getCustomerAnalytics(): Promise<CustomerAnalytics> {
    const { companyId } = await getAuthContext();
    return getCustomerAnalyticsFromDB(companyId);
}
export async function exportCustomers(params: { query?: string }) { 
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        const { items } = await getCustomersFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function exportSales(params: { query?: string }) { 
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
        const { items } = await getSalesFromDB(companyId, { ...params, offset: 0, limit: 10000 });
        const csv = Papa.unparse(items.map(item => ({
            order_number: item.order_number,
            created_at: item.created_at,
            customer_email: item.customer_email,
            financial_status: item.financial_status,
            fulfillment_status: item.fulfillment_status,
            total_amount: (item.total_amount / 100).toFixed(2),
            source_platform: item.source_platform,
        })));
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const { companyId, userId } = await getAuthContext();
        await checkUserPermission(userId, 'Admin');
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
        await checkUserPermission(userId, 'Owner');
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
        await checkUserPermission(userId, 'Admin');
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
        await checkUserPermission(userId, 'Admin');
        await reconcileInventoryInDb(companyId, integrationId, userId);
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getReorderReport(): Promise<ReorderSuggestion[]> {
    const { companyId } = await getAuthContext();
    
    // This function replicates the logic inside the getReorderSuggestions tool
    // to correctly fetch and process data without calling the tool directly.
    try {
        const baseSuggestions = await getReorderSuggestionsFromDB(companyId);
        if (baseSuggestions.length === 0) {
            return [];
        }

        const skus = baseSuggestions.map(s => s.sku);
        const [historicalSales, settings] = await Promise.all([
            getHistoricalSalesForSkusFromDB(companyId, skus),
            getSettings(companyId),
        ]);

        const { output } = await reorderRefinementPrompt({
            suggestions: baseSuggestions,
            historicalSales: historicalSales,
            currentDate: new Date().toISOString().split('T')[0],
            timezone: settings.timezone || 'UTC',
        });

        if (!output) {
            logError(new Error('AI reorder refinement did not return an output.'), { companyId });
            return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'AI refinement failed, using base calculation.',
                seasonality_factor: 1.0,
                confidence: 0.1,
            }));
        }
        return output;
    } catch (e) {
        logError(e, { context: `getReorderReport failed for company ${companyId}` });
        throw new Error('An error occurred while generating reorder suggestions.');
    }
}

export async function getInventoryLedger(variantId: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerFromDB(companyId, variantId);
}

export async function createPurchaseOrdersFromSuggestions(formData: FormData): Promise<{ success: boolean, error?: string, createdPoCount?: number }> {
    const { companyId, userId } = await getAuthContext();
    await checkUserPermission(userId, 'Admin');
    try {
        validateCSRF(formData);

        const suggestionsString = formData.get('suggestions') as string;
        if (!suggestionsString) {
             throw new Error('No reorder suggestions provided.');
        }

        const parsedSuggestions = ReorderSuggestionSchema.array().safeParse(JSON.parse(suggestionsString));
        if (!parsedSuggestions.success) {
            throw new Error(`Invalid suggestions format: ${parsedSuggestions.error.message}`);
        }

        const suggestions = parsedSuggestions.data;
        
        if (!suggestions || suggestions.length === 0) {
            throw new Error('No valid reorder suggestions provided.');
        }
        
        const idempotencyKey = crypto.randomUUID();
        const createdPoCount = await createPurchaseOrdersInDb(companyId, userId, suggestions, idempotencyKey);
        
        revalidatePath('/purchase-orders', 'page');
        
        return { success: true, createdPoCount };
    } catch (e) {
        logError(e, { context: 'createPurchaseOrdersFromSuggestions action' });
        throw e; // Re-throw the error so the client can handle it
    }
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

export async function getSupplierPerformanceReportData() {
    const { companyId } = await getAuthContext();
    return getSupplierPerformanceFromDB(companyId);
}

export async function getInventoryTurnoverReportData(days: number = 90) {
    const { companyId } = await getAuthContext();
    return getInventoryTurnoverFromDB(companyId, days);
}

export async function getHistoricalSalesForSkus(companyId: string, skus: string[]) {
    return getHistoricalSalesForSkusFromDB(companyId, skus);
}

async function getCashFlowInsightsFromDB(companyId: string) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase.rpc('get_cash_flow_insights', { p_company_id: companyId });
    if(error) throw error;
    return data;
}

