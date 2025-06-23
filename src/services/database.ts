/**
 * @fileoverview
 * This file provides functions to query your Supabase database. It uses the
 * Supabase admin client from /src/lib/supabase.ts and ensures all queries are
 * tenant-aware by using the companyId.
 */

import { supabaseAdmin } from '@/lib/supabase';
import { allMockData } from '@/lib/mock-data';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics } from '@/types';
import { format, subDays } from 'date-fns';

const USE_MOCK_DATA = !process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY;

/**
 * Retrieves the company ID for a given Firebase user UID.
 * This is used server-side after validating a Firebase token.
 * @param uid The Firebase user ID.
 * @returns A promise that resolves to the company ID string or null if not found.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    if (USE_MOCK_DATA) return 'default-company-id';
    
    try {
        const { data, error } = await supabaseAdmin
            .from('users')
            .select('company_id')
            .eq('firebase_uid', uid)
            .single();

        if (error) {
            if (error.code === 'PGRST116') { // 'PGRST116' is "exact one row not found"
                return null;
            }
            throw error;
        }
        return data?.company_id || null;
    } catch (error) {
        console.error('[DB Service] Supabase query failed in getCompanyIdForUser:', error);
        return null;
    }
}


/**
 * Executes a query to fetch data for chart generation from Supabase.
 * @param query A natural language description of the data needed.
 * @param companyId The ID of the company whose data is being queried.
 * @returns An array of data matching the query.
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    if (USE_MOCK_DATA) {
        const companyMockData = allMockData[companyId] || allMockData['default-company-id'];
        if (query.toLowerCase().includes('inventory value by category')) {
           return companyMockData.mockInventoryValueByCategory.map(d => ({ name: d.category, value: d.value }));
       }
       return [];
   }
    
    const lowerCaseQuery = query.toLowerCase();

    try {
        if (lowerCaseQuery.includes('inventory value by category') || lowerCaseQuery.includes('sales velocity')) {
             const { data, error } = await supabaseAdmin
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
        return [];
    } catch (error) {
        console.error('[DB Service] Query failed in getDataForChart. Returning empty array.', error);
        return [];
    }
}

export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
    if (USE_MOCK_DATA) {
        const mockProducts = allMockData[companyId]?.mockProducts || [];
        return mockProducts.filter(p => new Date(p.last_sold_date) < subDays(new Date(), 90));
    }
    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabaseAdmin
        .from('inventory')
        .select('*')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);
    
    if (error) {
        console.error('[DB Service] Query failed in getDeadStockFromDB:', error);
        return [];
    }
    return data as Product[];
}

export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    if (USE_MOCK_DATA) return allMockData[companyId]?.mockSuppliers || [];
    
    const { data, error } = await supabaseAdmin
        .from('vendors')
        .select('id, vendor_name, contact_info')
        .eq('company_id', companyId);

    if (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB:', error);
        return [];
    }

    return data.map(v => ({
        id: v.id,
        name: v.vendor_name,
        contact: v.contact_info,
        onTimeDeliveryRate: 95, // Mock data
        avgDeliveryTime: 5, // Mock data
    }));
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (USE_MOCK_DATA) return allMockData[companyId]?.mockInventoryItems || [];
    
    const { data, error } = await supabaseAdmin
        .from('inventory')
        .select('sku, name, quantity, cost, last_sold_date')
        .eq('company_id', companyId)
        .order('name');
    
    if (error) {
        console.error('[DB Service] Query failed in getInventoryItems:', error);
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

export async function getDeadStockPageData(companyId: string) {
    if (USE_MOCK_DATA) {
        const mockItems = allMockData[companyId]?.mockInventoryItems || [];
        const deadStockItems = mockItems.filter(item => new Date(item.lastSold) < subDays(new Date(), 90));
        const totalDeadStockValue = deadStockItems.reduce((acc, item) => acc + item.value, 0);
        return { deadStockItems, totalDeadStockValue };
    }
    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabaseAdmin
        .from('inventory')
        .select('sku, name, quantity, cost, last_sold_date')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);

    if (error) {
        console.error('[DB Service] Query failed in getDeadStockPageData:', error);
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

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    if (USE_MOCK_DATA) return allMockData[companyId]?.mockAlerts || [];
    console.warn("[DB Service] getAlertsFromDB is returning mock data as this requires a complex query.");
    return allMockData[companyId]?.mockAlerts || [];
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (USE_MOCK_DATA) return allMockData[companyId]?.mockDashboardMetrics;
    console.warn("[DB Service] getDashboardMetrics is returning mock data as this requires a complex query.");
    return allMockData[companyId]?.mockDashboardMetrics;
}
