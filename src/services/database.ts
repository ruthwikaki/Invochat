
'use server';

/**
 * @fileoverview
 * This file contains server-side functions for querying the Supabase database.
 * It uses a secure, user-authenticated Supabase client for all operations,
 * which respects Row Level Security (RLS) policies.
 *
 * All functions in this file will throw an error if the database query fails.
 * This allows the calling code (e.g., Server Components or Server Actions)
 * to handle the error appropriately by bubbling it up to the nearest `error.js` boundary.
 */

import { createClient } from '@/lib/supabase/server';
import type { DashboardMetrics, InventoryItem, Supplier, Alert } from '@/types';
import { subDays, differenceInDays, parseISO, isBefore } from 'date-fns';
import { cookies } from 'next/headers';

// This function creates a Supabase client authenticated as the current user.
// It is the secure way to access data on the server, enforcing RLS.
function createSecureServerClient() {
    const cookieStore = cookies();
    // The createClient function handles the check for missing env vars.
    return createClient(cookieStore);
}

// Corrected to remove onTimeDeliveryRate calculation which was based on a non-existent column.
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const supabase = createSecureServerClient();
  
  const { data: inventory, error: inventoryError } = await supabase
    .from('inventory')
    .select('quantity, cost, last_sold_date, reorder_point, name')
    .eq('company_id', companyId);

  if (inventoryError) {
    console.error('Error fetching inventory for dashboard:', inventoryError);
    throw new Error(`Failed to load dashboard data: ${inventoryError.message}`);
  }

  // If no inventory exists, return zeros but don't throw error
  if (!inventory || inventory.length === 0) {
    return {
      inventoryValue: 0,
      deadStockValue: 0,
      predictiveAlert: null
    };
  }

  const ninetyDaysAgo = subDays(new Date(), 90);
  const inventoryValue = inventory.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);
  const deadStockValue = inventory
      .filter(item => item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo))
      .reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);

  const lowStockItem = inventory.find(item => item.quantity <= item.reorder_point);
  const predictiveAlert = lowStockItem ? {
      item: lowStockItem.name,
      days: 7 // Placeholder
  } : null;

  return {
      inventoryValue: Math.round(inventoryValue),
      deadStockValue: Math.round(deadStockValue),
      predictiveAlert
  };
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
  const supabase = createSecureServerClient();
  const { data, error } = await supabase
    .from('inventory')
    .select('*')
    .eq('company_id', companyId)
    .order('name');
    
  if (error) {
    console.error('Error fetching inventory:', error);
    throw new Error(`Could not load inventory data: ${error.message}`);
  }
  return data || [];
}

export async function getDeadStockFromDB(companyId: string): Promise<InventoryItem[]> {
    const supabase = createSecureServerClient();
    const ninetyDaysAgo = subDays(new Date(), 90).toISOString();
    const { data, error } = await supabase
        .from('inventory')
        .select('*')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);

    if (error) {
        console.error('Error fetching dead stock:', error);
        throw new Error(`Could not load dead stock data: ${error.message}`);
    }
    return data || [];
}

export async function getDeadStockPageData(companyId: string) {
    const deadStock = await getDeadStockFromDB(companyId);
    if (deadStock.length === 0) {
        return { deadStock: [], totalValue: 0, totalUnits: 0, averageAge: 0 };
    }

    const totalValue = deadStock.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);
    const totalUnits = deadStock.reduce((sum, item) => sum + item.quantity, 0);

    const totalAgeInDays = deadStock.reduce((sum, item) => {
        if (item.last_sold_date) {
            return sum + differenceInDays(new Date(), parseISO(item.last_sold_date));
        }
        return sum;
    }, 0);
    const averageAge = deadStock.length > 0 ? totalAgeInDays / deadStock.length : 0;

    return {
        deadStock,
        totalValue: Math.round(totalValue),
        totalUnits,
        averageAge: Math.round(averageAge)
    };
}

// Note: This function depends on a custom RPC 'get_suppliers' in your database.
// An alternative is to query the 'vendors' table directly.
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    const supabase = createSecureServerClient();
    const { data, error } = await supabase.rpc('get_suppliers', { p_company_id: companyId });

    if (error) {
        console.error('Error fetching suppliers via RPC:', error);
        throw new Error(`Could not load supplier data: ${error.message}. Ensure the 'get_suppliers' function exists and is correctly defined in your database.`);
    }
    return data || [];
}

// This function directly queries the vendors table, including the 'account_number'
export async function getVendorsFromDB(companyId: string) {
    const supabase = createSecureServerClient();
    const { data, error } = await supabase
        .from('vendors')
        .select('id, vendor_name, contact_info, address, terms, account_number')
        .eq('company_id', companyId);

    if (error) {
        console.error('Error fetching vendors from DB', error);
        throw new Error(`Could not load vendor data: ${error.message}`);
    }
    return data.map(v => ({
        id: v.id,
        name: v.vendor_name, // Mapping to match Supplier type
        ...v
    })) || [];
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    const inventory = await getInventoryItems(companyId);

    const alerts: Alert[] = [];
    const ninetyDaysAgo = subDays(new Date(), 90);

    inventory.forEach(item => {
        // Low Stock Alert
        if (item.quantity <= item.reorder_point) {
            alerts.push({
                id: `low-${item.id}`,
                type: 'low_stock',
                title: 'Low Stock',
                message: `${item.name} is running low. Current stock is ${item.quantity}, reorder point is ${item.reorder_point}.`,
                severity: 'warning',
                timestamp: new Date().toISOString(),
                metadata: {
                    productId: item.id,
                    productName: item.name,
                    currentStock: item.quantity,
                    reorderPoint: item.reorder_point,
                    value: item.quantity * Number(item.cost)
                }
            });
        }

        // Dead Stock Alert
        if (item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo)) {
             alerts.push({
                id: `dead-${item.id}`,
                type: 'dead_stock',
                title: 'Dead Stock',
                message: `${item.name} has not sold in over 90 days.`,
                severity: 'info',
                timestamp: new Date().toISOString(),
                metadata: {
                    productId: item.id,
                    productName: item.name,
                    currentStock: item.quantity,
                    lastSoldDate: item.last_sold_date,
                    value: item.quantity * Number(item.cost)
                }
            });
        }
    });

    return alerts;
}

export async function getInventoryFromDB(companyId: string) {
    return getInventoryItems(companyId);
}

// Note: This function relies on a custom RPC 'get_chart_data' in your database.
// The success of this function depends on that RPC's implementation.
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    const supabase = createSecureServerClient();
    const lowerCaseQuery = query.toLowerCase();

    const { data, error } = await supabase.rpc('get_chart_data', {
        p_company_id: companyId,
        p_query: lowerCaseQuery
    });
    
    if (error) {
        console.error(`Error in getDataForChart for query "${query}":`, error);
        throw new Error(`Failed to get chart data: ${error.message}. Please ensure the 'get_chart_data' database function can handle the query.`);
    }

    if (!data) return [];
    
    if (lowerCaseQuery.includes('inventory value by category')) {
        return data.map((d: any) => ({ name: d.name, value: Math.round(d.value) }));
    }
    
    if (lowerCaseQuery.includes('slowest moving') || lowerCaseQuery.includes('dead stock')) {
        return data.map((d: any) => ({
            name: d.name,
            value: differenceInDays(new Date(), parseISO(d.last_sold_date))
        }));
    }

    return data || [];
}
