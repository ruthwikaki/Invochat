
'use server';

/**
 * @fileoverview
 * This file contains server-side functions for querying the Supabase database.
 *
 * It uses the Supabase Admin client (service_role) to bypass Row Level Security (RLS)
 * policies, which are causing infinite recursion errors. This is a deliberate
 * choice to work around flawed RLS policies in the database.
 *
 * SECURITY: All functions in this file MUST manually filter queries by `companyId`
 * to ensure users can only access their own data.
 */

import { supabaseAdmin } from '@/lib/supabase/admin';
import type { DashboardMetrics, InventoryItem, Supplier, Alert } from '@/types';
import { subDays, differenceInDays, parseISO, isBefore } from 'date-fns';

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 * The service role key is required for the app to function due to broken RLS policies.
 */
function getServiceRoleClient() {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. Please ensure SUPABASE_SERVICE_ROLE_KEY is set in your environment variables.');
    }
    return supabaseAdmin;
}


// Corrected to remove onTimeDeliveryRate calculation which was based on a non-existent column.
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const supabase = getServiceRoleClient();
  
  const [inventoryRes, vendorsRes, salesRes] = await Promise.all([
    supabase.from('inventory').select('quantity, cost, last_sold_date, reorder_point, name').eq('company_id', companyId),
    supabase.from('vendors').select('*', { count: 'exact', head: true }).eq('company_id', companyId),
    supabase.from('sales').select('total_amount').eq('company_id', companyId)
  ]);

  const { data: inventory, error: inventoryError } = inventoryRes;
  const { count: suppliersCount, error: suppliersError } = vendorsRes;
  const { data: sales, error: salesError } = salesRes;

  if (inventoryError || suppliersError || salesError) {
    console.error('Dashboard data fetching errors:', { inventoryError, suppliersError, salesError });
    const error = inventoryError || suppliersError || salesError;
    throw new Error(`Failed to load dashboard data: ${error?.message}`);
  }

  const totalSalesValue = (sales || []).reduce((sum, sale) => sum + (sale.total_amount || 0), 0);

  // If no inventory exists, return zeros but don't throw error
  if (!inventory || inventory.length === 0) {
    return {
      inventoryValue: 0,
      deadStockValue: 0,
      lowStockCount: 0,
      totalSKUs: 0,
      totalSuppliers: suppliersCount || 0,
      totalSalesValue: Math.round(totalSalesValue),
    };
  }

  const ninetyDaysAgo = subDays(new Date(), 90);
  const inventoryValue = inventory.reduce((sum, item) => sum + ((item.quantity || 0) * Number(item.cost || 0)), 0);
  
  const deadStockItems = inventory.filter(item => 
    item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo)
  );
  
  const deadStockValue = deadStockItems.reduce((sum, item) => sum + ((item.quantity || 0) * Number(item.cost || 0)), 0);
  
  const lowStockCount = inventory.filter(item => (item.quantity || 0) <= (item.reorder_point || 0)).length;

  return {
      inventoryValue: Math.round(inventoryValue),
      deadStockValue: Math.round(deadStockValue),
      lowStockCount: lowStockCount,
      totalSKUs: inventory.length,
      totalSuppliers: suppliersCount || 0,
      totalSalesValue: Math.round(totalSalesValue)
  };
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
  const supabase = getServiceRoleClient();
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
    const supabase = getServiceRoleClient();
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

/**
 * This function directly queries the vendors table to get a list of all suppliers
 * for a given company, ensuring a single, consistent method for data retrieval.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('vendors')
        .select('id, vendor_name, contact_info, address, terms, account_number')
        .eq('company_id', companyId);

    if (error) {
        console.error('Error fetching suppliers from DB', error);
        throw new Error(`Could not load supplier data: ${error.message}`);
    }
    
    // Map the database fields to the consistent 'Supplier' type
    return data?.map(v => ({
        id: v.id,
        name: v.vendor_name,
        contact_info: v.contact_info,
        address: v.address,
        terms: v.terms,
        account_number: v.account_number,
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

// These are the tables we want to expose to the user.
// We are explicitly listing them to match what the AI has been told it can query.
const USER_FACING_TABLES = ['inventory', 'vendors', 'sales', 'purchase_orders'];

/**
 * Fetches the schema and sample data for user-facing tables.
 * @param companyId The ID of the company to fetch data for.
 * @returns An array of objects, each containing a table name and sample rows.
 */
export async function getDatabaseSchemaAndData(companyId: string): Promise<{ tableName: string; rows: any[] }[]> {
  const supabase = getServiceRoleClient();
  const results: { tableName: string; rows: any[] }[] = [];

  for (const tableName of USER_FACING_TABLES) {
    const { data, error } = await supabase
      .from(tableName)
      .select('*')
      .eq('company_id', companyId)
      .limit(10);

    if (error) {
      console.warn(`[Database Explorer] Could not fetch data for table '${tableName}'. It might not exist or be configured for the current company. Error: ${error.message}`);
      // Push an empty result so the UI can still render the table name
      results.push({ tableName, rows: [] });
    } else {
      results.push({
        tableName,
        rows: data || [],
      });
    }
  }

  return results;
}
