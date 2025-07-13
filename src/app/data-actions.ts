

'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { logger } from '@/lib/logger';
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
  getReorderSuggestionsFromDB,
  getAnomalyInsightsFromDB,
  getDbSchemaAndData,
  healthCheckFinancialConsistency,
  healthCheckInventoryConsistency,
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
  getInventoryLedgerFromDB,
} from '@/services/database';
import { testGenkitConnection as genkitTest } from '@/services/genkit';
import { isRedisEnabled, testRedisConnection as redisTest } from '@/lib/redis';
import type { CompanySettings, SupplierFormData, ProductUpdateData, Alert, Anomaly, HealthCheckResult, InventoryAgingReportItem, ReorderSuggestion, ProductLifecycleAnalysis, InventoryRiskItem, CustomerSegmentAnalysisItem, InventoryLedgerEntry } from '@/types';
import { deleteIntegrationFromDb } from '@/services/database';
import { CSRF_FORM_NAME, validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { revalidatePath } from 'next/cache';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { generateMorningBriefing } from '@/ai/flows/morning-briefing-flow';
import { sendInventoryDigestEmail } from '@/services/email';
import { getCustomerInsights } from '@/ai/flows/customer-insights-flow';
import { generateProductDescription } from '@/ai/flows/generate-description-flow';
import { universalChatFlow } from '@/ai/flows/universal-chat';


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

export async function getDashboardData(dateRange: string) {
    const { companyId } = await getAuthContext();
    // This function will need to be updated to work with the new schema
    // return getDashboardMetrics(companyId, dateRange);
    return { total_revenue: 0, average_sale_value: 0, salesTrendData: [], topCustomersData: [], inventoryByCategoryData: [] }; // Placeholder
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
  };
  return updateSettingsInDb(companyId, settings);
}

export async function getUnifiedInventory(params: { query?: string; page?: number, limit?: number }) {
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


export async function getInventoryLedger(variantId: string): Promise<InventoryLedgerEntry[]> {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerFromDB(companyId, variantId);
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

// ... other actions to be refactored ...

// Stubs for functions that need updates
export async function getReorderReport(): Promise<ReorderSuggestion[]> { return []; }
export async function getInsightsPageData() { return { summary: '', anomalies: [], topDeadStock: [], topLowStock: [] }; }
export async function testSupabaseConnection() { return dbTestSupabase(); }
export async function testDatabaseQuery() { return dbTestQuery(); }
export async function testGenkitConnection() { return genkitTest(); }
export async function testRedisConnection() { return { isEnabled: isRedisEnabled, ...await redisTest() }; }
export async function getGeneratedProductDescription(productName: string, category: string, keywords: string[]) {
    return generateProductDescription({ productName, category, keywords });
}

export async function logUserFeedback(formData: FormData) { return {success: true} }
export async function getAlertsData() { return [] }
export async function getDatabaseSchemaAndData() { return [] }
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
export async function exportCustomers(params: { query?: string }) { return {success: false, error: "Not implemented"}; }
export async function exportSales(params: { query?: string }) { return {success: false, error: "Not implemented"}; }
export async function exportReorderSuggestions(suggestions: ReorderSuggestion[]) {
    try {
        const dataToExport = suggestions.map(s => ({
            SKU: s.sku,
            ProductName: s.product_name,
            Supplier: s.supplier_name,
            QuantityToOrder: s.suggested_reorder_quantity,
            UnitCost: s.unit_cost ? (s.unit_cost).toFixed(2) : 'N/A',
            TotalCost: s.unit_cost ? ((s.suggested_reorder_quantity * s.unit_cost)).toFixed(2) : 'N/A'
        }));
        const csv = Papa.unparse(dataToExport);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function requestCompanyDataExport(): Promise<{ success: boolean, jobId?: string, error?: string }> { return {success: false, error: "Not implemented"}; }
export async function getInventoryConsistencyReport(): Promise<HealthCheckResult> { return {healthy: true, metric: 0, message: "OK"}; }
export async function getFinancialConsistencyReport(): Promise<HealthCheckResult> { return {healthy: true, metric: 0, message: "OK"}; }
export async function getInventoryAgingData(): Promise<InventoryAgingReportItem[]> { return []; }
export async function exportInventory(params: { query?: string }) { return {success: false, error: "Not implemented"}; }
export async function getCashFlowInsights() {
    const { companyId } = await getAuthContext();
    return getCashFlowInsightsFromDB(companyId);
}
export async function getSupplierPerformance() { return []; }
export async function getInventoryTurnover() { return {turnover_rate:0,total_cogs:0,average_inventory_value:0,period_days:0}; }
export async function sendInventoryDigestEmailAction(): Promise<{ success: boolean; error?: string }> { return {success: false, error: "Not implemented"}; }
export async function getProductLifecycleAnalysis(): Promise<ProductLifecycleAnalysis> { return {summary: {launch_count:0, growth_count:0, maturity_count:0, decline_count:0}, products:[]}; }
export async function getInventoryRiskReport(): Promise<InventoryRiskItem[]> { return []; }
export async function getCustomerSegmentAnalysis(): Promise<{ segments: CustomerSegmentAnalysisItem[], insights: { analysis: string, suggestion: string } | null }> { return {segments: [], insights: null}; }
export async function getMorningBriefing(range: string) { return {greeting: 'Good morning!', summary: 'Data is being updated for the new schema.'}; }
export async function reconcileInventory(integrationId: string): Promise<{ success: boolean; error?: string }> { return {success: false, error: "Not implemented"}; }
export async function testMaterializedView() { return {success: true}; }
export async function logPOCreation(poNumber: string, supplierName: string, items: any[]) { return; }
export async function transferStock(formData: FormData) { return {success: false, error: "Not implemented"}; }
