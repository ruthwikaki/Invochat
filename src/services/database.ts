
'use server';

/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 */

import { supabaseAdmin, isSupabaseAdminEnabled } from '@/lib/supabase';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics, UserProfile } from '@/types';
import { format, subDays, isBefore, parseISO } from 'date-fns';

/**
 * Retrieves the company ID for a given Firebase user UID.
 */
export async function getCompanyIdForUser(userId: string): Promise<string | null> {
  if (!isSupabaseAdminEnabled) {
    console.error('Supabase Admin not initialized');
    return null;
  }

  const { data, error } = await supabaseAdmin!
    .from('user_profiles')
    .select('company_id')
    .eq('id', userId)
    .single();

  if (error || !data) {
    return null;
  }

  return data.company_id;
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
                .from('products')
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
    if (!isSupabaseAdminEnabled) return [];

    const products = await getInventoryItems(companyId);
    const ninetyDaysAgo = subDays(new Date(), 90);
    
    return products.filter(p => 
        p.last_sold_date && isBefore(parseISO(p.last_sold_date), ninetyDaysAgo)
    );
}

export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    // NOTE: The new schema doesn't have a vendors/suppliers table.
    // This function is kept for compatibility with the UI but returns an empty array.
    console.warn("[DB Service] getSuppliersFromDB is not implemented for the current schema.");
    return [];
}

export async function getInventoryItems(companyId: string): Promise<Product[]> {
  if (!isSupabaseAdminEnabled) return [];

  const { data, error } = await supabaseAdmin!
    .from('products')
    .select('*')
    .eq('company_id', companyId);
    
  if (error) {
      console.error('[DB Service] Error fetching inventory items:', error.message);
      return [];
  }

  return data || [];
}

export async function getDeadStockPageData(companyId: string) {
    if (!isSupabaseAdminEnabled) return { deadStockItems: [], totalDeadStockValue: 0 };
    
    const products = await getInventoryItems(companyId);
    const ninetyDaysAgo = subDays(new Date(), 90);

    const deadStockProducts = products.filter(p => 
        p.last_sold_date && isBefore(parseISO(p.last_sold_date), ninetyDaysAgo)
    );
    
    const deadStockItems: InventoryItem[] = deadStockProducts.map(p => ({
        id: p.sku,
        name: p.name,
        quantity: p.quantity,
        value: p.quantity * p.cost,
        lastSold: p.last_sold_date ? format(parseISO(p.last_sold_date), 'yyyy-MM-dd') : 'N/A'
    }));

    const totalDeadStockValue = deadStockItems.reduce((sum, item) => sum + item.value, 0);

    return { deadStockItems, totalDeadStockValue };
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
  if (!isSupabaseAdminEnabled) return [];

  const products = await getInventoryItems(companyId);
  const alerts: Alert[] = [];

  const lowStock = products.filter(p => p.quantity < 10);
  lowStock.forEach(p => {
    alerts.push({
      id: `low-${p.id}`,
      type: 'Low Stock',
      item: p.name,
      message: `Low stock alert: ${p.name} (${p.quantity} units remaining)`,
      date: new Date().toISOString(),
      resolved: false
    });
  });

  return alerts;
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  if (!isSupabaseAdminEnabled) {
    return { inventoryValue: 0, deadStockValue: 0, lowStockItems: 0, onTimeDeliveryRate: 0, predictiveAlert: null };
  }

  const products = await getInventoryItems(companyId);

  const inventoryValue = products.reduce((sum, p) => sum + (p.quantity * p.cost), 0);
  const lowStockItems = products.filter(p => p.quantity < 10).length;
  
  const ninetyDaysAgo = subDays(new Date(), 90);
  const deadStockValue = products
    .filter(p => p.last_sold_date && isBefore(parseISO(p.last_sold_date), ninetyDaysAgo))
    .reduce((sum, p) => sum + (p.quantity * p.cost), 0);

  // onTimeDeliveryRate and predictiveAlert require more complex data not in the current schema
  return { inventoryValue, deadStockValue, lowStockItems, onTimeDeliveryRate: 0, predictiveAlert: null };
}

