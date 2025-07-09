

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
  createPurchaseOrderInDb,
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
  deleteLocationFromDB,
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
  getPurchaseOrderAnalyticsFromDB,
  getSalesAnalyticsFromDB,
  getSuppliersWithPerformanceFromDB,
} from '@/services/database';
import {
    generateAnomalyExplanation,
} from '@/ai/flows/anomaly-explanation-flow';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import type { Alert, Anomaly, CompanySettings, InventoryUpdateData, LocationFormData, PurchaseOrder, PurchaseOrderCreateInput, PurchaseOrderUpdateInput, ReorderSuggestion, ReceiveItemsFormInput, SupplierFormData, SaleCreateInput } from '@/types';
import { sendPurchaseOrderEmail } from '@/services/email';
import { deleteIntegrationFromDb } from '@/services/database';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME, validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { ai } from '@/ai/genkit';

// Helper function to get company and user IDs
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
    const companyId = user.app_metadata.company_id;
    if (!companyId) throw new Error('Company ID not found for user.');
    return { companyId, userId: user.id };
}

// Dashboard
export async function getDashboardData(dateRange: string) {
    const { companyId } = await getAuthContext();
    return getDashboardMetrics(companyId, dateRange);
}

// Dead Stock
export async function getDeadStockData() {
    const { companyId } = await getAuthContext();
    return getDeadStockPageData(companyId);
}

// Alerts
export async function getAlertsData(): Promise<Alert[]> {
    const { companyId } = await getAuthContext();
    return getAlertsFromDB(companyId);
}

// Database Explorer
export async function getDatabaseSchemaAndData() {
    const { companyId } = await getAuthContext();
    return getDbSchemaAndData(companyId);
}

// Settings
export async function getCompanySettings() {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function updateCompanySettings(formData: FormData) {
  const { companyId } = await getAuthContext();
  const settings = {
    dead_stock_days: Number(formData.get('dead_stock_days')),
    fast_moving_days: Number(formData.get('fast_moving_days')),
    overstock_multiplier: Number(formData.get('overstock_multiplier')),
    high_value_threshold: Number(formData.get('high_value_threshold')),
    predictive_stock_days: Number(formData.get('predictive_stock_days')),
  };
  return updateSettingsInDb(companyId, settings);
}

// Insights
export async function getInsightsPageData() {
    const { companyId } = await getAuthContext();
    const [rawAnomalies, topDeadStockData, topLowStock] = await Promise.all([
        getAnomalyInsightsFromDB(companyId),
        getDeadStockPageData(companyId),
        getAlertsData(),
    ]);

    const explainedAnomalies = await Promise.all(
        rawAnomalies.map(async (anomaly) => {
            const date = new Date(anomaly.date);
            const explanation = await generateAnomalyExplanation({
                anomaly,
                dateContext: {
                    dayOfWeek: date.toLocaleDateString('en-US', { weekday: 'long' }),
                    month: date.toLocaleDateString('en-US', { month: 'long' }),
                    season: 'Summer', // This is a placeholder
                    knownHoliday: undefined, // This would require a holiday API
                },
            });
            return { ...anomaly, ...explanation };
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

// Inventory
export async function getUnifiedInventory(params: { query?: string; category?: string; location?: string, supplier?: string, page?: number, limit?: number }) {
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
        const skusString = formData.get('skus') as string;
        if (!skusString) throw new Error('No SKUs provided for deletion.');
        
        const skus = JSON.parse(skusString);
        await softDeleteInventoryItemsFromDb(companyId, skus, userId);
        
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateInventoryItem(sku: string, data: InventoryUpdateData) {
    try {
        const { companyId } = await getAuthContext();
        const updatedItem = await updateInventoryItemInDb(companyId, sku, data);
        revalidatePath('/inventory');
        return { success: true, updatedItem };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getInventoryLedger(sku: string) {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerForSkuFromDB(companyId, sku);
}

export async function exportInventory(params: { query?: string; category?: string; location?: string, supplier?: string }) {
    try {
        const { companyId } = await getAuthContext();
        // Fetch all items that match the filter, without pagination limits
        const { items } = await getUnifiedInventoryFromDB(companyId, { ...params, limit: 10000, offset: 0 });
        const csv = Papa.unparse(items);
        return { success: true, data: csv };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Team Management
export async function getTeamMembers() {
    const { companyId } = await getAuthContext();
    return getTeamMembersFromDB(companyId);
}

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        const email = formData.get('email') as string;
        // In a real app, we'd fetch the company name from the DB
        await inviteUserToCompanyInDb(companyId, 'Your Company', email);
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
        
        return await removeTeamMemberFromDb(memberId, companyId, userId);
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
        
        return await updateTeamMemberRoleInDb(memberId, companyId, newRole);
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Reordering Suggestions
export async function getReorderSuggestions(): Promise<ReorderSuggestion[]> {
    const { companyId } = await getAuthContext();
    return getReorderSuggestionsFromDB(companyId);
}

export async function createPurchaseOrdersFromSuggestions(suggestions: ReorderSuggestion[]): Promise<{ success: boolean; createdPoCount: number; error?: string }> {
  try {
    const { companyId } = await getAuthContext();
    const poBySupplier = suggestions.reduce((acc, s) => {
        if (!s.supplier_id) return acc;
        if (!acc[s.supplier_id]) {
            acc[s.supplier_id] = {
                supplier_id: s.supplier_id,
                po_number: `PO-${Date.now()}-${s.supplier_id.substring(0, 4)}`,
                order_date: new Date(),
                status: 'draft',
                items: []
            };
        }
        acc[s.supplier_id].items.push({
            sku: s.sku,
            quantity_ordered: s.suggested_reorder_quantity,
            unit_cost: s.unit_cost || 0
        });
        return acc;
    }, {} as Record<string, any>);

    let createdPoCount = 0;
    for (const supplierId in poBySupplier) {
        const poData = poBySupplier[supplierId];
        await createPurchaseOrderInDb(companyId, poData);
        createdPoCount++;
    }
    
    revalidatePath('/purchase-orders');
    return { success: true, createdPoCount };
  } catch(e) {
    return { success: false, createdPoCount: 0, error: getErrorMessage(e) };
  }
}

// Purchase Orders
export async function getPurchaseOrders(params: { query?: string, page: number }) {
    const { companyId } = await getAuthContext();
    const limit = 25;
    const offset = (params.page - 1) * limit;
    return getPurchaseOrdersFromDB(companyId, { ...params, limit, offset });
}

export async function getPurchaseOrderAnalytics() {
    const { companyId } = await getAuthContext();
    return getPurchaseOrderAnalyticsFromDB(companyId);
}

export async function getSuppliersData() {
    const { companyId } = await getAuthContext();
    return getSuppliersWithPerformanceFromDB(companyId);
}

export async function getPurchaseOrderById(id: string) {
    const { companyId } = await getAuthContext();
    return getPurchaseOrderByIdFromDB(id, companyId);
}

export async function createPurchaseOrder(data: PurchaseOrderCreateInput) {
    try {
        const { companyId } = await getAuthContext();
        await createPurchaseOrderInDb(companyId, data);
        revalidatePath('/purchase-orders');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updatePurchaseOrder(id: string, data: PurchaseOrderUpdateInput) {
    try {
        const { companyId } = await getAuthContext();
        await updatePurchaseOrderInDb(id, companyId, data);
        revalidatePath('/purchase-orders');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deletePurchaseOrder(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        const poId = formData.get('poId') as string;
        await deletePurchaseOrderFromDb(poId, companyId);
        revalidatePath('/purchase-orders');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function emailPurchaseOrder(formData: FormData): Promise<{success: boolean, error?: string}> {
    try {
        const { companyId } = await getAuthContext();
        const poId = formData.get('poId') as string;
        const po = await getPurchaseOrderByIdFromDB(poId, companyId);
        if (!po) throw new Error("Purchase Order not found.");
        
        await sendPurchaseOrderEmail(po);
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function receivePurchaseOrderItems(data: ReceiveItemsFormInput): Promise<{success: boolean, error?: string}> {
    try {
        const { companyId } = await getAuthContext();
        await receivePurchaseOrderItemsInDB(data.poId, companyId, data.items);
        revalidatePath(`/purchase-orders/${data.poId}`);
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Channel Fees
export async function getChannelFees() {
    const { companyId } = await getAuthContext();
    return getChannelFeesFromDB(companyId);
}

export async function upsertChannelFee(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        const feeData = {
            channel_name: formData.get('channel_name') as string,
            percentage_fee: parseFloat(formData.get('percentage_fee') as string),
            fixed_fee: parseFloat(formData.get('fixed_fee') as string),
        };
        await upsertChannelFeeInDB(companyId, feeData);
        revalidatePath('/settings');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Locations
export async function getLocations() {
    const { companyId } = await getAuthContext();
    return getLocationsFromDB(companyId);
}
export async function getLocationById(id: string) {
    const { companyId } = await getAuthContext();
    return getLocationByIdFromDB(id, companyId);
}
export async function createLocation(data: LocationFormData) {
    try {
        const { companyId } = await getAuthContext();
        await createLocationInDB(companyId, data);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function updateLocation(id: string, data: LocationFormData) {
    try {
        const { companyId } = await getAuthContext();
        await updateLocationInDB(id, companyId, data);
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function deleteLocation(formData: FormData) {
    try {
        const { companyId } = await getAuthContext();
        const id = formData.get('id') as string;
        await deleteLocationFromDB(id, companyId);
        revalidatePath('/locations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Suppliers
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
        const id = formData.get('id') as string;
        await deleteSupplierFromDb(id, companyId);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Integrations
export async function getIntegrations() {
    const { companyId } = await getAuthContext();
    return getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(formData: FormData) {
    try {
        const cookieStore = cookies();
        const csrfTokenFromCookie = cookieStore.get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        
        const { companyId } = await getAuthContext();
        const id = formData.get('integrationId') as string;
        await deleteIntegrationFromDb(id, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// Customers
export async function getCustomersData(params: { query?: string, page: number }) {
    const { companyId } = await getAuthContext();
    const limit = 25;
    const offset = (params.page - 1) * limit;
    return getCustomersFromDB(companyId, { ...params, limit, offset });
}

export async function getCustomerAnalytics() {
    const { companyId } = await getAuthContext();
    return getCustomerAnalyticsFromDB(companyId);
}

export async function deleteCustomer(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId } = await getAuthContext();
        const id = formData.get('id') as string;
        await deleteCustomerFromDb(id, companyId);
        revalidatePath('/customers');
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

// Sales
export async function searchProductsForSale(query: string) {
    const { companyId } = await getAuthContext();
    return searchProductsForSaleInDB(companyId, query);
}

export async function recordSale(formData: FormData): Promise<{ success: boolean, sale?: any, error?: string }> {
    try {
        const cookieStore = cookies();
        const csrfToken = cookieStore.get('csrf_token')?.value;
        validateCSRF(formData, csrfToken);

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

// Export
export async function requestCompanyDataExport(): Promise<{ success: boolean, jobId?: string, error?: string }> {
    try {
        const { companyId, userId } = await getAuthContext();
        const job = await createExportJobInDb(companyId, userId);
        // In a real app, this would trigger a background worker.
        // For now, we just log it.
        logger.info(`[Export] Job ${job.id} created for company ${companyId}.`);
        return { success: true, jobId: job.id };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
