
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import {
  getDashboardMetrics,
  getSettings,
  updateSettingsInDb,
  getInventoryCategoriesFromDB,
  getUnifiedInventoryFromDB,
  getSupplierByIdFromDB,
  createSupplierInDb,
  updateSupplierInDb,
  deleteSupplierFromDb,
  softDeleteInventoryItemsFromDb,
  getInventoryLedgerForSkuFromDB,
  getCustomersFromDB,
  deleteCustomerFromDb,
  searchProductsForSaleInDB,
  recordSaleInDB,
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
  getReorderReportFromDB,
  getInventoryHealthScoreFromDB,
  findProfitLeaksFromDB,
  getAbcAnalysisFromDB
} from '@/services/database';
import { testGenkitConnection as genkitTest } from '@/services/genkit';
import { isRedisEnabled, testRedisConnection as redisTest } from '@/lib/redis';
import type { CompanySettings, SupplierFormData, SaleCreateInput, ProductUpdateData } from '@/types';
import { deleteIntegrationFromDb } from '@/services/database';
import { CSRF_COOKIE_NAME, validateCSRF } from '@/lib/csrf';
import Papa from 'papaparse';
import { revalidatePath } from 'next/cache';

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

// --- Report Actions ---

export async function getDeadStockReport() {
    const { companyId } = await getAuthContext();
    return getDeadStockReportFromDB(companyId);
}

export async function getReorderReport() {
    const { companyId } = await getAuthContext();
    return getReorderReportFromDB(companyId);
}

export async function getInventoryHealthScore() {
    const { companyId } = await getAuthContext();
    return getInventoryHealthScoreFromDB(companyId);
}

export async function getProfitLeaks() {
    const { companyId } = await getAuthContext();
    return findProfitLeaksFromDB(companyId);
}

export async function getAbcAnalysis(metric: 'revenue' | 'units' | 'profit', period: 'last30' | 'last90' | 'last365') {
    const { companyId } = await getAuthContext();
    return getAbcAnalysisFromDB(companyId, metric, period);
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
