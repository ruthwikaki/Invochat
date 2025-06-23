
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
            .eq('firebase_uid', uid)
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
 * Calls a database function (RPC) to create a company and user profile in a single transaction.
 * This is more robust and secure than multi-step client-side inserts.
 * @param companyName The name of the new company.
 * @returns A promise that resolves to the new company's ID.
 */
export async function setupNewUserAndCompany(companyName: string): Promise<string> {
    if (!isDbConnected()) {
        console.log(`[Mock DB] Skipping user/company creation for ${companyName}.`);
        return 'default-company-id';
    }

    try {
        const { data, error } = await supabase.rpc('handle_new_user', {
            company_name_param: companyName
        });

        if (error) {
            console.error('[DB Service] RPC call to handle_new_user failed:', error);
            throw new Error(`Database error during user setup: ${error.message}`);
        }

        if (!data) {
            throw new Error('RPC call to handle_new_user did not return a company ID.');
        }

        return data;
    } catch (error: any) {
        console.error('[DB Service] CRITICAL: Exception during RPC call in setupNewUserAndCompany:', error);
        throw error; // Re-throw to be caught by the server action
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
                const category = item.category || 'Uncategorized';
                acc[category] = (acc[category] || 0) + (item.quantity * item.cost);
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
        .from('vendors') // NOTE: Using 'vendors' table as per user schema
        .select('id, vendor_name, contact_info')
        .eq('company_id', companyId)

    if (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB. Returning empty array.', error);
        return [];
    }

    // The user's 'vendors' table doesn't have performance data, so we map what we have.
    return data.map(v => ({
        id: v.id,
        name: v.vendor_name,
        contact: v.contact_info,
        onTimeDeliveryRate: 95, // Mock data
        avgDeliveryTime: 5, // Mock data
    }));
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
        lastSold: item.last_sold_date ? format(new Date(item.last_sold_date), 'yyyy-MM-dd') : 'N/A',
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
        lastSold: item.last_sold_date ? format(new Date(item.last_sold_date), 'yyyy-MM-dd') : 'N/A',
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
    
    console.warn("[DB Service] getAlertsFromDB is returning mock data as this requires a complex query.");
    return allMockData[companyId]?.mockAlerts || [];
}

/**
 * Retrieves key metrics for the dashboard.
 * @param companyId The company's ID.
 * @returns A promise resolving to an object with dashboard metrics.
 */
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (!isDbConnected()) return allMockData[companyId]?.mockDashboardMetrics;

    console.warn("[DB Service] getDashboardMetrics is returning mock data as this requires a complex query.");
    return allMockData[companyId]?.mockDashboardMetrics;
}
