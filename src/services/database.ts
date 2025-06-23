
/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 * NOTE: This service layer is currently configured to use MOCK DATA when
 * the Supabase admin client is not available. This allows the app to be
 * fully interactive for demonstration purposes without a database connection.
 */

import { supabaseAdmin, isSupabaseAdminEnabled } from '@/lib/supabase';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics, UserProfile } from '@/types';
import { allMockData } from '@/lib/mock-data';
import { format, subDays } from 'date-fns';

/**
 * Retrieves the user's full profile from Supabase, including company details.
 * In mock mode, it provides a default profile for the demo user.
 * @param firebaseUid The Firebase UID of the user.
 * @returns A promise that resolves to the UserProfile or null if not found.
 */
export async function getUserProfile(firebaseUid: string): Promise<UserProfile | null> {
    if (!isSupabaseAdminEnabled) {
        // Mock implementation
        return {
            id: 'demo-user-id',
            firebase_uid: firebaseUid,
            email: 'demo@example.com',
            company_id: 'default-company-id',
            role: 'admin',
            company: {
                id: 'default-company-id',
                name: 'InvoChat Demo',
                invite_code: 'DEMO123'
            }
        };
    }

    // Real implementation
    try {
        const { data, error } = await supabaseAdmin!
            .from('users')
            .select(`
                id,
                firebase_uid,
                email,
                company_id,
                role,
                company:companies (
                    id,
                    name,
                    invite_code
                )
            `)
            .eq('firebase_uid', firebaseUid)
            .single();
        
        if (error) {
            if (error.code === 'PGRST116') return null;
            throw error;
        }

        return data as UserProfile;

    } catch (error) {
        console.error('[DB Service] Error fetching user profile:', error);
        throw error;
    }
}


/**
 * Retrieves the company ID for a given Firebase user UID.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    if (!isSupabaseAdminEnabled) return 'default-company-id';
    
    try {
        const { data, error } = await supabaseAdmin!
            .from('users')
            .select('company_id')
            .eq('firebase_uid', uid)
            .single();

        if (error) {
            if (error.code === 'PGRST116') return null;
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
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    if (!isSupabaseAdminEnabled) {
        const lowerCaseQuery = query.toLowerCase();
         if (lowerCaseQuery.includes('inventory value by category') || lowerCaseQuery.includes('sales velocity')) {
            const data = allMockData[companyId]?.mockInventoryValueByCategory || [];
            return data.map(d => ({ name: d.category, value: d.value }));
         }
        return [];
    }
    
    const lowerCaseQuery = query.toLowerCase();

    try {
        if (lowerCaseQuery.includes('inventory value by category') || lowerCaseQuery.includes('sales velocity')) {
             const { data, error } = await supabaseAdmin!
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
    if (!isSupabaseAdminEnabled) {
        const mockData = allMockData[companyId] || allMockData['default-company-id'];
        return mockData.mockProducts.filter(p => new Date(p.last_sold_date) < subDays(new Date(), 90));
    }

    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabaseAdmin!
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
    if (!isSupabaseAdminEnabled) {
        return allMockData[companyId]?.mockSuppliers || allMockData['default-company-id'].mockSuppliers;
    }
    
    const { data, error } = await supabaseAdmin!
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
        onTimeDeliveryRate: 95,
        avgDeliveryTime: 5,
    }));
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (!isSupabaseAdminEnabled) {
        return allMockData[companyId]?.mockInventoryItems || allMockData['default-company-id'].mockInventoryItems;
    }
    
    const { data, error } = await supabaseAdmin!
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
    if (!isSupabaseAdminEnabled) {
        const mockData = allMockData[companyId] || allMockData['default-company-id'];
        const items = mockData.mockInventoryItems.filter(p => new Date(p.lastSold) < subDays(new Date(), 90));
        const totalValue = items.reduce((acc, item) => acc + item.value, 0);
        return { deadStockItems: items, totalDeadStockValue: totalValue };
    }

    const ninetyDaysAgo = format(subDays(new Date(), 90), 'yyyy-MM-dd');
    const { data, error } = await supabaseAdmin!
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
    if (!isSupabaseAdminEnabled) {
        return allMockData[companyId]?.mockAlerts || allMockData['default-company-id'].mockAlerts;
    }
    console.warn("[DB Service] getAlertsFromDB is returning an empty array as the real query is complex.");
    return [];
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (!isSupabaseAdminEnabled) {
        return allMockData[companyId]?.mockDashboardMetrics || allMockData['default-company-id'].mockDashboardMetrics;
     }

    console.warn("[DB Service] getDashboardMetrics is returning partially real data.");
    
    const { data, error } = await supabaseAdmin!
        .from('inventory')
        .select('quantity, cost')
        .eq('company_id', companyId);

    if (error || !data) {
        return {
            inventoryValue: 0, deadStockValue: 0, onTimeDeliveryRate: 0, predictiveAlert: null
        };
    }
    
    const inventoryValue = data.reduce((acc, item) => acc + (item.quantity * item.cost), 0);

    return {
        inventoryValue: inventoryValue,
        deadStockValue: 0,
        onTimeDeliveryRate: 0,
        predictiveAlert: null
    };
}
