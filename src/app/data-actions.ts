'use server';

import { createClient } from '@/lib/supabase/server';
import { 
    getDashboardMetrics, 
    getInventoryFromDB, 
    getDeadStockPageData,
    getVendorsFromDB,
    getAlertsFromDB
} from '@/services/database';


async function getCompanyIdForCurrentUser(): Promise<string> {
    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();

    // The company_id should be stored in the user's metadata (app_metadata for Supabase)
    // This is set via a custom claim or a DB trigger after signup.
    const companyId = user?.app_metadata?.company_id;

    if (!companyId) {
        throw new Error("User is not associated with a company.");
    }
    return companyId;
}

export async function getDashboardData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDashboardMetrics(companyId);
}

export async function getInventoryData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getInventoryFromDB(companyId);
}

export async function getDeadStockData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getVendorsFromDB(companyId);
}

export async function getAlertsData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getAlertsFromDB(companyId);
}
