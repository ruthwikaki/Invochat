
'use server';

/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 */

import { supabaseAdmin, isSupabaseAdminEnabled } from '@/lib/supabase';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics, UserProfile } from '@/types';
import { format, subDays } from 'date-fns';

/**
 * Retrieves the user's full profile from Supabase, including company details.
 * @param firebaseUid The Firebase UID of the user.
 * @returns A promise that resolves to the UserProfile or null if not found.
 */
export async function getUserProfile(firebaseUid: string): Promise<UserProfile | null> {
    if (!isSupabaseAdminEnabled) {
        console.error("[DB Service] Supabase Admin client is not available. Cannot fetch user profile.");
        throw new Error("Database connection is not configured.");
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
            if (error.code === 'PGRST116') return null; // 'PGRST116' means no rows found, which is a valid case.
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
    if (!isSupabaseAdminEnabled) {
        console.error("[DB Service] Supabase Admin client is not available. Cannot fetch company ID.");
        return null;
    }
    
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
        console.error("[DB Service] Supabase Admin client is not available. Cannot get data for chart.");
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
        // Return empty for other queries for now
        return [];
    } catch (error) {
        console.error('[DB Service] Query failed in getDataForChart. Returning empty array.', error);
        return [];
    }
}

export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
    if (!isSupabaseAdminEnabled) {
        console.error("[DB Service] Supabase Admin client is not available. Cannot get dead stock.");
        return [];
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
        console.error("[DB Service] Supabase Admin client is not available. Cannot get suppliers.");
        return [];
    }
    
    const { data, error } = await supabaseAdmin!
        .from('vendors')
        .select('id, vendor_name, contact_info') // Assuming these are the columns
        .eq('company_id', companyId);

    if (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB:', error);
        return [];
    }

    // Mapping might need to be adjusted based on the actual schema
    return data.map(v => ({
        id: v.id,
        name: v.vendor_name,
        contact: v.contact_info,
        onTimeDeliveryRate: 95, // Example static value
        avgDeliveryTime: 5,     // Example static value
    }));
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (!isSupabaseAdminEnabled) {
        console.error("[DB Service] Supabase Admin client is not available. Cannot get inventory items.");
        return [];
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
        console.error("[DB Service] Supabase Admin client is not available. Cannot get dead stock page data.");
        return { deadStockItems: [], totalDeadStockValue: 0 };
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
        console.error("[DB Service] Supabase Admin client is not available. Cannot get alerts.");
        return [];
     }
    console.warn("[DB Service] getAlertsFromDB is returning an empty array as the real query is complex and not yet implemented.");
    return [];
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (!isSupabaseAdminEnabled) {
        console.error("[DB Service] Supabase Admin client is not available. Cannot get dashboard metrics.");
        return { inventoryValue: 0, deadStockValue: 0, onTimeDeliveryRate: 0, predictiveAlert: null };
     }

    try {
        const { data, error } = await supabaseAdmin!
            .from('inventory')
            .select('quantity, cost, last_sold_date')
            .eq('company_id', companyId);

        if (error || !data) {
            if (error) console.error('[DB Service] Query failed in getDashboardMetrics:', error);
            return { inventoryValue: 0, deadStockValue: 0, onTimeDeliveryRate: 0, predictiveAlert: null };
        }
        
        const inventoryValue = data.reduce((acc, item) => acc + (item.quantity * item.cost), 0);
        
        const ninetyDaysAgo = subDays(new Date(), 90);
        const deadStockValue = data.filter(item => item.last_sold_date && new Date(item.last_sold_date) < ninetyDaysAgo)
                                   .reduce((acc, item) => acc + (item.quantity * item.cost), 0);

        // Predictive alerts and on-time delivery are complex and would require more data. Returning static for now.
        return {
            inventoryValue: inventoryValue,
            deadStockValue: deadStockValue,
            onTimeDeliveryRate: 95.2, // Example value
            predictiveAlert: null      // Example value
        };
    } catch(error) {
        console.error('[DB Service] Exception in getDashboardMetrics:', error);
        return { inventoryValue: 0, deadStockValue: 0, onTimeDeliveryRate: 0, predictiveAlert: null };
    }
}
