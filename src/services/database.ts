
'use server';

/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 */

import { supabaseAdmin, isSupabaseAdminEnabled } from '@/lib/supabase';
import type { InventoryItem, Vendor, Alert, DashboardMetrics } from '@/types';
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
                .from('inventory')
                .select('category, quantity, cost')
                .eq('company_id', companyId);

            if (error) throw error;

            const aggregated = data.reduce((acc, item) => {
                const category = item.category || 'Uncategorized';
                acc[category] = (acc[category] || 0) + (item.quantity * Number(item.cost));
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

export async function getDeadStockFromDB(companyId: string): Promise<InventoryItem[]> {
    if (!isSupabaseAdminEnabled) return [];

    const inventory = await getInventoryFromDB(companyId);
    const ninetyDaysAgo = subDays(new Date(), 90);
    
    return inventory.filter(p => 
        p.last_sold_date && isBefore(parseISO(p.last_sold_date), ninetyDaysAgo)
    );
}

export async function getVendorsFromDB(companyId: string): Promise<Vendor[]> {
    if (!isSupabaseAdminEnabled) return [];

    const { data, error } = await supabaseAdmin!
        .from('vendors')
        .select('*')
        .eq('company_id', companyId);
        
    if (error) {
        console.error('[DB Service] Error fetching vendors:', error.message);
        return [];
    }

    return data || [];
}

export async function getInventoryFromDB(companyId: string): Promise<InventoryItem[]> {
  if (!isSupabaseAdminEnabled) return [];

  const { data, error } = await supabaseAdmin!
    .from('inventory')
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
    
    const deadStockItems = await getDeadStockFromDB(companyId);

    const totalDeadStockValue = deadStockItems.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);

    return { deadStockItems, totalDeadStockValue };
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
  if (!isSupabaseAdminEnabled) return [];

  const inventory = await getInventoryFromDB(companyId);
  const alerts: Alert[] = [];

  const lowStock = inventory.filter(p => p.quantity < p.reorder_point);
  lowStock.forEach(p => {
    alerts.push({
      id: `low-${p.id}`,
      type: 'Low Stock',
      item: p.name,
      message: `Low stock alert: ${p.name} (${p.quantity} units remaining, reorder point is ${p.reorder_point})`,
      date: new Date().toISOString(),
      resolved: false
    });
  });

  return alerts;
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  if (!isSupabaseAdminEnabled) {
    return { totalProducts: 0, totalValue: 0, lowStockItems: 0, deadStockValue: 0 };
  }

  const inventory = await getInventoryFromDB(companyId);

  const totalProducts = inventory.length;
  const totalValue = inventory.reduce((sum, p) => sum + (p.quantity * Number(p.cost)), 0);
  const lowStockItems = inventory.filter(p => p.quantity < p.reorder_point).length;
  
  const ninetyDaysAgo = subDays(new Date(), 90);
  const deadStockValue = inventory
    .filter(p => p.last_sold_date && isBefore(parseISO(p.last_sold_date), ninetyDaysAgo))
    .reduce((sum, p) => sum + (p.quantity * Number(p.cost)), 0);

  return { totalProducts, totalValue, lowStockItems, deadStockValue };
}
