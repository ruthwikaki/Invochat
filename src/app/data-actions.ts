
'use server';

import { createClient } from '@/lib/supabase/server';
import { 
    getDashboardMetrics, 
    getInventoryFromDB, 
    getDeadStockPageData,
    getVendorsFromDB,
    getAlertsFromDB
} from '@/services/database';

const SUPABASE_CONFIGURED = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

async function getCompanyIdForCurrentUser(): Promise<string> {
    if (!SUPABASE_CONFIGURED) {
        // In a real app, you might want to return mock data or a specific error object.
        // For now, we throw an error to make it clear that the DB is not set up.
        throw new Error("Database is not configured. Please set Supabase environment variables.");
    }

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
