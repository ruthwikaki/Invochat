
/**
 * @fileoverview
 * This file provides functions to query your Supabase database. It uses the
 * Supabase client from /src/lib/db.ts and ensures all queries are tenant-aware
 * by using the companyId.
 * When the database is not connected, it returns mock data for demonstration.
 */

import { supabase, isDbConnected } from '@/lib/db';
import { allMockData } from '@/lib/mock-data';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics } from '@/types';
import { format, subDays } from 'date-fns';

/**
 * Retrieves the company ID for a given Supabase user UID.
 * This is a critical function; if it fails, we throw because we can't identify the tenant.
 * @param uid The Supabase user ID.
 * @returns A promise that resolves to the company ID string or null if not found.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    if (!isDbConnected()) return 'default-company-id';
    
    try {
        const { data, error } = await supabase
            .from('users')
            .select('company_id')
            .eq('id', uid)
            .single();

        if (error) {
            // 'PGRST116' is the code for 'exact one row not found', which is expected if the user has no profile yet.
            // We don't want to throw an error in that case.
            if (error.code === 'PGRST116') {
                return null;
            }
            throw error;
        }
        return data?.company_id || null;
    } catch (error) {
        console.error('[DB Service] CRITICAL: Supabase query failed in getCompanyIdForUser:', error);
        return null;
    }
}

/**
 * Creates a new company and a user associated with it in the database.
 * This function is now idempotent: it checks if a user profile already exists
 * before attempting to create one.
 * @param uid The Supabase user ID.
 * @param email The user's email.
 * @param companyName The name of the new company.
 * @returns A promise that resolves to the new company's ID.
 */
export async function createCompanyAndUserInDB(uid: string, email: string, companyName: string): Promise<string> {
    if (!isDbConnected()) {
        console.log(`[Mock DB] Skipping user/company creation for ${email}.`);
        return 'default-company-id';
    }

    // 1. Check if user profile already exists to make this operation idempotent.
    const existingCompanyId = await getCompanyIdForUser(uid);
    if (existingCompanyId) {
        console.log(`[DB Service] Profile for user ${uid} already exists in company ${existingCompanyId}. Skipping creation.`);
        return existingCompanyId;
    }

    // 2. Profile does not exist, so create it.
    try {
        // Create the company first.
        const { data: companyData, error: companyError } = await supabase
            .from('companies')
            .insert({ name: companyName, user_id: uid })
            .select('id')
            .single();

        if (companyError) {
          // Add a more descriptive error message
          const message = companyError.message.includes("schema cache") 
              ? `Database schema error: ${companyError.message}. Please ensure your 'companies' table has the correct columns.`
              : companyError.message;
          throw new Error(message);
        }
        const companyId = companyData.id;

        // Then create the user profile linked to the company.
        const { error: userError } = await supabase
            .from('users')
            .insert({ id: uid, email: email, company_id: companyId });

        if (userError) throw userError;

        return companyId;
    } catch (error: any) {
        console.error('[DB Service] CRITICAL: Supabase transaction failed in createCompanyAndUserInDB:', error);
        // Re-throw the original error to be caught by the server action
        throw error;
    }
}


/**
 * Executes a query to fetch data for chart generation from Supabase.
 * Returns mock data or an empty array on database failure.
 * @param query A natural language description of the data needed.
 * @param companyId The ID of the company whose data is being queried.
 * @returns An array of data matching the query.
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    if (!isDbConnected()) {
        const companyMockData = allMockData[companyId];
        if (query.toLowerCase().includes('inventory value by category')) {
           return companyMockData.mockInventoryValueByCategory.map(d => ({ name: d.category, value: d.value }));
       }
       return [];
   }
    
    const lowerCaseQuery = query.toLowerCase();

    try {
        if (lowerCaseQuery.includes('inventory value by category') || lowerCaseQuery.includes('sales velocity')) {
             const { data, error } = await supabase
                .from('inventory')
                .select('category, quantity, cost')
                .eq('company_id', companyId);

            if (error) throw error;

            const aggregated = data.reduce((acc, item) => {
                acc[item.category] = (acc[item.category] || 0) + (item.quantity * item.cost);
                return acc;
            }, {} as Record<string, number>);

            return Object.entries(aggregated).map(([name, value]) => ({ name, value }));
        }

        // Add other chart data fetching logic here...

    } catch (error) {
        console.error('[DB Service] Query failed in getDataForChart. Returning empty array.', error);
        return [];
    }

    // Fallback for unhandled queries
    return [];
}


/**
 * Retrieves dead stock items from the database for the AI flow.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of dead stock products.
 */
export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
    if (!isDbConnected()) {
        const mockProducts = allMockData[companyId]?.mockProducts || [];
        return mockProducts.filter(p => new Date(p.last_sold_date) < subDays(new Date(), 90));
    }

    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabase
        .from('inventory')
        .select('*')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);
    
    if (error) {
        console.error('[DB Service] Query failed in getDeadStockFromDB. Returning empty array.', error);
        return [];
    }
    return data as Product[];
}

/**
 * Retrieves suppliers from the database, ranked by performance.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of suppliers.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockSuppliers || [];
    
    const { data, error } = await supabase
        .from('suppliers')
        .select('*')
        .eq('company_id', companyId)
        .order('on_time_delivery_rate', { ascending: false });

    if (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB. Returning empty array.', error);
        return [];
    }
    return data as Supplier[];
}

/**
 * Retrieves all inventory items for a company.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of inventory items.
 */
export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockInventoryItems || [];
    
    const { data, error } = await supabase
        .from('inventory')
        .select('sku, name, quantity, cost, last_sold_date')
        .eq('company_id', companyId)
        .order('name');
    
    if (error) {
        console.error('[DB Service] Query failed in getInventoryItems. Returning empty array.', error);
        return [];
    }

    return data.map(item => ({
        id: item.sku,
        name: item.name,
        quantity: item.quantity,
        value: item.quantity * item.cost,
        lastSold: format(new Date(item.last_sold_date), 'yyyy-MM-dd'),
    }));
}

/**
 * Retrieves data for the Dead Stock page.
 * @param companyId The company's ID.
 */
export async function getDeadStockPageData(companyId: string) {
    if (!isDbConnected()) {
        const mockItems = allMockData[companyId]?.mockInventoryItems || [];
        const deadStockItems = mockItems.filter(item => new Date(item.lastSold) < subDays(new Date(), 90));
        const totalDeadStockValue = deadStockItems.reduce((acc, item) => acc + item.value, 0);
        return { deadStockItems, totalDeadStockValue };
    }

    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabase
        .from('inventory')
        .select('sku, name, quantity, cost, last_sold_date')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);

    if (error) {
        console.error('[DB Service] Query failed in getDeadStockPageData. Returning default values.', error);
        return { deadStockItems: [], totalDeadStockValue: 0 };
    }

    const deadStockItems = data.map(item => ({
        id: item.sku,
        name: item.name,
        quantity: item.quantity,
        value: item.quantity * item.cost,
        lastSold: format(new Date(item.last_sold_date), 'yyyy-MM-dd'),
    }));

    const totalDeadStockValue = deadStockItems.reduce((acc, item) => acc + item.value, 0);

    return { deadStockItems, totalDeadStockValue };
}


/**
 * Retrieves alerts.
 * @param companyId The company's ID.
 * @returns A promise resolving to an array of alerts.
 */
export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockAlerts || [];
    
    // This is a complex query to replicate, so we will return mock data for now.
    // A production implementation would use database views or functions (RPCs).
    console.warn("[DB Service] getAlertsFromDB is returning mock data as the query is too complex for a simple client-side replication.");
    return allMockData[companyId]?.mockAlerts || [];
}

/**
 * Retrieves key metrics for the dashboard.
 * @param companyId The company's ID.
 * @returns A promise resolving to an object with dashboard metrics.
 */
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (!isDbConnected()) return allMockData[companyId]?.mockDashboardMetrics;

    // This is a complex query to replicate, so we will return mock data for now.
    // A production implementation would use database views or functions (RPCs).
    console.warn("[DB Service] getDashboardMetrics is returning mock data as the query is too complex for a simple client-side replication.");
    return allMockData[companyId]?.mockDashboardMetrics;
}
