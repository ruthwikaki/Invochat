
'use server';

/**
 * @fileoverview
 * This file contains server-side functions for querying the Supabase database.
 *
 * It uses the Supabase Admin client (service_role) to bypass Row Level Security (RLS)
 * policies. This is a deliberate choice for this application context.
 *
 * SECURITY: All functions in this file MUST manually filter queries by `companyId`
 * to ensure users can only access their own data.
 */

import { supabaseAdmin } from '@/lib/supabase/admin';
import type { DashboardMetrics, InventoryItem, Supplier, Alert } from '@/types';
import { subDays, differenceInDays, parseISO, isBefore } from 'date-fns';
import { redisClient, isRedisEnabled } from '@/lib/redis';

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 */
function getServiceRoleClient() {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. Please ensure SUPABASE_SERVICE_ROLE_KEY is set in your environment variables.');
    }
    return supabaseAdmin;
}


export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const cacheKey = `company:${companyId}:dashboard`;

  if (isRedisEnabled) {
    try {
        const cachedData = await redisClient.get(cacheKey);
        if (cachedData) {
            console.log(`[Cache] HIT for dashboard metrics: ${cacheKey}`);
            return JSON.parse(cachedData);
        }
        console.log(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
    } catch (error) {
        console.error(`[Redis] Error getting cache for ${cacheKey}:`, error);
    }
  }

  const supabase = getServiceRoleClient();
  
  // Use the materialized view for core inventory metrics where possible
  const metricsPromise = supabase
    .from('company_dashboard_metrics')
    .select('total_skus, inventory_value, low_stock_count')
    .eq('company_id', companyId)
    .single();

  // Run other queries in parallel
  const vendorsPromise = supabase.from('vendors').select('*', { count: 'exact', head: true }).eq('company_id', companyId);
  const salesPromise = supabase.from('sales').select('total_amount').eq('company_id', companyId);
  const deadStockItemsPromise = supabase
    .from('inventory')
    .select('quantity, cost')
    .eq('company_id', companyId)
    .lt('last_sold_date', subDays(new Date(), 90).toISOString());
  
  // Queries for charts, executed via a secure RPC function
  const salesTrendQuery = `
    SELECT
      TO_CHAR(sale_date, 'YYYY-MM-DD') as date,
      SUM(total_amount) as "Sales"
    FROM sales
    WHERE company_id = '${companyId}'
    GROUP BY 1
    ORDER BY 1 ASC
    LIMIT 30
  `;
  const salesTrendPromise = supabase.rpc('execute_dynamic_query', { query_text: salesTrendQuery.trim().replace(/;/g, '') });
  
  const inventoryByCategoryQuery = `
    SELECT
      COALESCE(category, 'Uncategorized') as name,
      SUM(quantity * cost) as value
    FROM inventory
    WHERE company_id = '${companyId}'
    GROUP BY 1
    HAVING SUM(quantity * cost) > 0
    ORDER BY 2 DESC
  `;
  const inventoryByCategoryPromise = supabase.rpc('execute_dynamic_query', { query_text: inventoryByCategoryQuery.trim().replace(/;/g, '') });

  const [
    metricsRes,
    vendorsRes,
    salesRes,
    deadStockItemsRes,
    salesTrendRes,
    inventoryByCategoryRes
  ] = await Promise.all([
    metricsPromise,
    vendorsPromise,
    salesPromise,
    deadStockItemsPromise,
    salesTrendPromise,
    inventoryByCategoryPromise
  ]);

  const { data: metricsData, error: metricsError } = metricsRes;
  const { count: suppliersCount, error: suppliersError } = vendorsRes;
  const { data: sales, error: salesError } = salesRes;
  const { data: deadStockItems, error: deadStockError } = deadStockItemsRes;
  const { data: salesTrendData, error: salesTrendError } = salesTrendRes;
  const { data: inventoryByCategoryData, error: inventoryByCategoryError } = inventoryByCategoryRes;
  
  // Check for an error from the materialized view query specifically
  if (metricsError && metricsError.code === '42P01') { // 42P01: undefined_table
      console.warn('[Dashboard] Materialized view `company_dashboard_metrics` not found. Falling back to full query. Run the setup SQL for better performance.');
      // If the view doesn't exist, we must fall back to the full query.
      // This is a simplified fallback for demonstration. A production app might handle this more robustly.
      return getDashboardMetricsWithFullQuery(companyId);
  }

  const firstError = suppliersError || salesError || deadStockError || salesTrendError || inventoryByCategoryError;
  if (firstError) {
    console.error('Dashboard data fetching error:', firstError);
    throw new Error(firstError.message);
  }

  const totalSalesValue = (sales || []).reduce((sum, sale) => sum + (sale.total_amount || 0), 0);
  const deadStockValue = (deadStockItems || []).reduce((sum, item) => sum + ((item.quantity || 0) * Number(item.cost || 0)), 0);

  const finalMetrics: DashboardMetrics = {
      inventoryValue: Math.round(metricsData?.inventory_value || 0),
      deadStockValue: Math.round(deadStockValue),
      lowStockCount: metricsData?.low_stock_count || 0,
      totalSKUs: metricsData?.total_skus || 0,
      totalSuppliers: suppliersCount || 0,
      totalSalesValue: Math.round(totalSalesValue),
      salesTrendData: salesTrendData || [],
      inventoryByCategoryData: inventoryByCategoryData || [],
  };

  if (isRedisEnabled) {
      try {
          // Cache the result for 5 minutes (300 seconds)
          await redisClient.set(cacheKey, JSON.stringify(finalMetrics), 'EX', 300);
          console.log(`[Cache] SET for dashboard metrics: ${cacheKey}`);
      } catch (error) {
          console.error(`[Redis] Error setting cache for ${cacheKey}:`, error);
      }
  }

  return finalMetrics;
}


// Fallback function if materialized view does not exist.
async function getDashboardMetricsWithFullQuery(companyId: string): Promise<DashboardMetrics> {
  const supabase = getServiceRoleClient();
  
  const inventoryPromise = supabase.from('inventory').select('quantity, cost, last_sold_date, reorder_point, name, category').eq('company_id', companyId);
  const vendorsPromise = supabase.from('vendors').select('*', { count: 'exact', head: true }).eq('company_id', companyId);
  const salesPromise = supabase.from('sales').select('total_amount').eq('company_id', companyId);

  const salesTrendQuery = `SELECT TO_CHAR(sale_date, 'YYYY-MM-DD') as date, SUM(total_amount) as "Sales" FROM sales WHERE company_id = '${companyId}' GROUP BY 1 ORDER BY 1 ASC LIMIT 30`;
  const salesTrendPromise = supabase.rpc('execute_dynamic_query', { query_text: salesTrendQuery.trim().replace(/;/g, '') });
  
  const inventoryByCategoryQuery = `SELECT COALESCE(category, 'Uncategorized') as name, SUM(quantity * cost) as value FROM inventory WHERE company_id = '${companyId}' GROUP BY 1 HAVING SUM(quantity * cost) > 0 ORDER BY 2 DESC`;
  const inventoryByCategoryPromise = supabase.rpc('execute_dynamic_query', { query_text: inventoryByCategoryQuery.trim().replace(/;/g, '') });

  const [
    inventoryRes,
    vendorsRes,
    salesRes,
    salesTrendRes,
    inventoryByCategoryRes
  ] = await Promise.all([inventoryPromise, vendorsRes, salesPromise, salesTrendPromise, inventoryByCategoryPromise]);

  const { data: inventory, error: inventoryError } = inventoryRes;
  // ... (rest of the original function logic)
    const { count: suppliersCount, error: suppliersError } = vendorsRes;
    const { data: sales, error: salesError } = salesRes;
    const { data: salesTrendData, error: salesTrendError } = salesTrendRes;
    const { data: inventoryByCategoryData, error: inventoryByCategoryError } = inventoryByCategoryRes;

    const firstError = inventoryError || suppliersError || salesError || salesTrendError || inventoryByCategoryError;
    if (firstError) {
        console.error('Dashboard data fetching error:', firstError);
        throw new Error(firstError.message);
    }
     const totalSalesValue = (sales || []).reduce((sum, sale) => sum + (sale.total_amount || 0), 0);

    if (!inventory || inventory.length === 0) {
        return { inventoryValue: 0, deadStockValue: 0, lowStockCount: 0, totalSKUs: 0, totalSuppliers: suppliersCount || 0, totalSalesValue: Math.round(totalSalesValue), salesTrendData: salesTrendData || [], inventoryByCategoryData: inventoryByCategoryData || [] };
    }

    const ninetyDaysAgo = subDays(new Date(), 90);
    const inventoryValue = inventory.reduce((sum, item) => sum + ((item.quantity || 0) * Number(item.cost || 0)), 0);
    const deadStockItems = inventory.filter(item => item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo));
    const deadStockValue = deadStockItems.reduce((sum, item) => sum + ((item.quantity || 0) * Number(item.cost || 0)), 0);
    const lowStockCount = inventory.filter(item => (item.quantity || 0) <= (item.reorder_point || 0)).length;

    return { inventoryValue: Math.round(inventoryValue), deadStockValue: Math.round(deadStockValue), lowStockCount: lowStockCount, totalSKUs: inventory.length, totalSuppliers: suppliersCount || 0, totalSalesValue: Math.round(totalSalesValue), salesTrendData: salesTrendData || [], inventoryByCategoryData: inventoryByCategoryData || [] };
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
