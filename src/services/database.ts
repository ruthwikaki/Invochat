
'use server';

/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 * It connects to the actual database tables to fetch real-time data.
 */

import { supabaseAdmin, isSupabaseAdminEnabled, supabaseAdminError } from '@/lib/supabase/admin';
import type { InventoryItem, Vendor, Alert, DashboardMetrics } from '@/types';
import { subDays, isBefore, parseISO, isAfter } from 'date-fns';

// A helper function to ensure we don't proceed if Supabase isn't configured.
function checkSupabaseAdmin() {
  if (!isSupabaseAdminEnabled) {
    console.error(`[DB Service] ${supabaseAdminError}`);
    throw new Error("Database admin client is not configured.");
  }
  return supabaseAdmin;
}

/**
 * Fetches all inventory items for a given company.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an array of inventory items.
 */
export async function getInventoryFromDB(companyId: string): Promise<InventoryItem[]> {
  const supabase = checkSupabaseAdmin();
  try {
    const { data, error } = await supabase
      .from('inventory')
      .select('*')
      .eq('company_id', companyId)
      .order('name');
      
    if (error) throw error;
    return data || [];
  } catch (error) {
    console.error('[DB Service] Error in getInventoryFromDB:', error);
    return [];
  }
}

/**
 * Fetches all vendors/suppliers for a given company.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an array of vendors.
 */
export async function getVendorsFromDB(companyId: string): Promise<Vendor[]> {
  const supabase = checkSupabaseAdmin();
  try {
    const { data, error } = await supabase
      .from('vendors')
      .select('*')
      .eq('company_id', companyId);
      
    if (error) throw error;
    return data || [];
  } catch (error) {
    console.error('[DB Service] Error in getVendorsFromDB:', error);
    return [];
  }
}

/**
 * Fetches dead stock items (not sold in the last 90 days) for a given company.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an array of dead stock inventory items.
 */
export async function getDeadStockFromDB(companyId: string): Promise<InventoryItem[]> {
  const supabase = checkSupabaseAdmin();
  try {
    const ninetyDaysAgo = subDays(new Date(), 90).toISOString();
    const { data, error } = await supabase
      .from('inventory')
      .select('*')
      .eq('company_id', companyId)
      .lt('last_sold_date', ninetyDaysAgo);

    if (error) throw error;
    return data || [];
  } catch (error) {
    console.error('[DB Service] Error in getDeadStockFromDB:', error);
    return [];
  }
}

/**
 * Fetches key metrics for the dashboard.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an object with dashboard metrics.
 */
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  try {
    const inventory = await getInventoryFromDB(companyId);
    const deadStockItems = await getDeadStockFromDB(companyId);

    const totalProducts = inventory.length;
    const totalValue = inventory.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);
    const lowStockItems = inventory.filter(item => item.quantity < item.reorder_point).length;
    const deadStockValue = deadStockItems.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);

    return { totalProducts, totalValue, lowStockItems, deadStockValue };
  } catch (error) {
    console.error('[DB Service] Error in getDashboardMetrics:', error);
    return { totalProducts: 0, totalValue: 0, lowStockItems: 0, deadStockValue: 0 };
  }
}

/**
 * Fetches data specifically for the Dead Stock page.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an object with dead stock items and their total value.
 */
export async function getDeadStockPageData(companyId: string) {
  try {
    const deadStockItems = await getDeadStockFromDB(companyId);
    const totalDeadStockValue = deadStockItems.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);
    return { deadStockItems, totalDeadStockValue };
  } catch (error) {
    console.error('[DB Service] Error in getDeadStockPageData:', error);
    return { deadStockItems: [], totalDeadStockValue: 0 };
  }
}

/**
 * Generates a list of alerts based on inventory status.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an array of alert objects.
 */
export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
  try {
    const inventory = await getInventoryFromDB(companyId);
    const alerts: Alert[] = [];

    // Low Stock Alerts
    const lowStock = inventory.filter(item => item.quantity < item.reorder_point);
    lowStock.forEach(item => {
      alerts.push({
        id: `low-${item.id}`,
        type: 'Low Stock',
        item: item.name,
        message: `Low stock alert: ${item.name} (${item.quantity} units remaining, reorder point is ${item.reorder_point})`,
        date: new Date().toISOString(),
        resolved: false
      });
    });

    return alerts;
  } catch (error) {
    console.error('[DB Service] Error in getAlertsFromDB:', error);
    return [];
  }
}

/**
 * Executes a query to fetch data for chart generation from Supabase.
 * This function interprets a natural language query to decide which data to fetch.
 * @param query The natural language query from the user.
 * @param companyId The UUID of the company.
 * @returns A promise that resolves to an array of data points for charting.
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
  const supabase = checkSupabaseAdmin();
  const lowerCaseQuery = query.toLowerCase();

  try {
    // Inventory Value by Category
    if (lowerCaseQuery.includes('inventory value by category') || lowerCaseQuery.includes('sales velocity')) {
      const { data, error } = await supabase
        .from('inventory')
        .select('category, quantity, cost')
        .eq('company_id', companyId);

      if (error) throw error;

      const aggregated = data.reduce((acc, item) => {
          const category = item.category || 'Uncategorized';
          acc[category] = (acc[category] || 0) + (item.quantity * Number(item.cost));
          return acc;
      }, {} as Record<string, number>);

      return Object.entries(aggregated).map(([name, value]) => ({ name, value: Math.round(value) }));
    }

    // Warehouse Distribution
    if (lowerCaseQuery.includes('warehouse distribution')) {
        const { data, error } = await supabase
            .from('inventory')
            .select('quantity, warehouse_locations ( name )')
            .eq('company_id', companyId);

        if (error) throw error;

        const aggregated = data.reduce((acc, item) => {
            const locationName = (item.warehouse_locations as { name: string } | null)?.name || 'Unknown Location';
            acc[locationName] = (acc[locationName] || 0) + item.quantity;
            return acc;
        }, {} as Record<string, number>);

        return Object.entries(aggregated).map(([name, value]) => ({ name, value }));
    }
    
    // Dead Stock Value by Category
    if (lowerCaseQuery.includes('dead stock') && lowerCaseQuery.includes('category')) {
      const deadStockItems = await getDeadStockFromDB(companyId);
      const aggregated = deadStockItems.reduce((acc, item) => {
        const category = item.category || 'Uncategorized';
        acc[category] = (acc[category] || 0) + (item.quantity * Number(item.cost));
        return acc;
      }, {} as Record<string, number>);

      return Object.entries(aggregated).map(([name, value]) => ({ name, value: Math.round(value) }));
    }

    // Supplier Performance (On-time delivery rate)
    if (lowerCaseQuery.includes('supplier performance') || lowerCaseQuery.includes('on time')) {
        const { data, error } = await supabase
            .from('purchase_orders')
            .select('vendor_name, status, delivery_date, expected_date')
            .eq('company_id', companyId)
            .in('status', ['Completed', 'Partially Received']);

        if (error) throw error;
        
        const performance = data.reduce((acc, order) => {
            if (!order.vendor_name) return acc;
            if (!acc[order.vendor_name]) {
                acc[order.vendor_name] = { onTime: 0, total: 0 };
            }
            acc[order.vendor_name].total++;
            if (order.delivery_date && order.expected_date && !isAfter(parseISO(order.delivery_date), parseISO(order.expected_date))) {
                 acc[order.vendor_name].onTime++;
            }
            return acc;
        }, {} as Record<string, { onTime: number, total: number }>);

        return Object.entries(performance).map(([name, { onTime, total }]) => ({
            name,
            value: total > 0 ? Math.round((onTime / total) * 100) : 0, // as a percentage
        }));
    }

    console.warn(`[DB Service] getDataForChart could not handle the query: "${query}"`);
    return [];
  } catch (error) {
    console.error('[DB Service] Error in getDataForChart:', error);
    return [];
  }
}
