
/**
 * @fileoverview
 * This file provides functions to query your Supabase database. It uses the
 * Supabase admin client from /src/lib/supabase.ts and ensures all queries are
 * tenant-aware by using the companyId.
 */

import { supabaseAdmin } from '@/lib/supabase';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics, UserProfile } from '@/types';
import { format, subDays } from 'date-fns';

/**
 * Retrieves the user's full profile from Supabase, including company details.
 * @param firebaseUid The Firebase UID of the user.
 * @returns A promise that resolves to the UserProfile or null if not found.
 */
export async function getUserProfile(firebaseUid: string): Promise<UserProfile | null> {
    if (!supabaseAdmin) {
        console.error('[DB Service] Supabase admin client is not available.');
        return null;
    }

    try {
        const { data, error } = await supabaseAdmin
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
            if (error.code === 'PGRST116') return null; // Not found, which is a valid state for a new user
            throw error;
        }

        return data as UserProfile;

    } catch (error) {
        console.error('[DB Service] Error fetching user profile:', error);
        throw error; // Re-throw to be handled by the caller
    }
}


/**
 * Retrieves the company ID for a given Firebase user UID.
 * This is used server-side after validating a Firebase token.
 * @param uid The Firebase user ID.
 * @returns A promise that resolves to the company ID string or null if not found.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    if (!supabaseAdmin) return null;
    
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
    if (!supabaseAdmin) return [];
    
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
        // Add more query interpretations here as needed
        return [];
    } catch (error) {
        console.error('[DB Service] Query failed in getDataForChart. Returning empty array.', error);
        return [];
    }
}

export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
    if (!supabaseAdmin) return [];

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
    return data;
}

export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    if (!supabaseAdmin) return [];
    
    const { data, error } = await supabaseAdmin
        .from('vendors')
        .select('id, vendor_name, contact_info')
        .eq('company_id', companyId);

    if (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB:', error);
        return [];
    }

    // NOTE: onTimeDeliveryRate and avgDeliveryTime are not in the schema, returning mock values.
    // A real implementation would calculate this from delivery data.
    return data.map(v => ({
        id: v.id,
        name: v.vendor_name,
        contact: v.contact_info,
        onTimeDeliveryRate: 95, // Placeholder data
        avgDeliveryTime: 5, // Placeholder data
    }));
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (!supabaseAdmin) return [];
    
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
    if (!supabaseAdmin) return { deadStockItems: [], totalDeadStockValue: 0 };

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
    if (!supabaseAdmin) return [];
    // For now, since this is a complex query, we return an empty array.
    // A real implementation would query for low stock, etc.
    console.warn("[DB Service] getAlertsFromDB is returning an empty array as the real query is complex.");
    return [];
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
     if (!supabaseAdmin) {
        return {
            inventoryValue: 0,
            deadStockValue: 0,
            onTimeDeliveryRate: 0,
            predictiveAlert: null
        };
     }

    // This is a simplified query. A full implementation would be more complex.
    console.warn("[DB Service] getDashboardMetrics is returning partially real data.");
    
    const { data, error } = await supabaseAdmin
        .from('inventory')
        .select('quantity, cost')
        .eq('company_id', companyId);

    if (error || !data) {
        return {
            inventoryValue: 0,
            deadStockValue: 0,
            onTimeDeliveryRate: 0,
            predictiveAlert: null
        };
    }
    
    const inventoryValue = data.reduce((acc, item) => acc + (item.quantity * item.cost), 0);

    return {
        inventoryValue: inventoryValue,
        deadStockValue: 0, // Requires more complex query
        onTimeDeliveryRate: 0, // Requires more complex query
        predictiveAlert: null // Requires more complex query
    };
}
