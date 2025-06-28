
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
import type { DashboardMetrics, Supplier, Alert, CompanySettings, DeadStockItem } from '@/types';
import { subDays, differenceInDays, parseISO, isBefore } from 'date-fns';
import { redisClient, isRedisEnabled, invalidateCompanyCache } from '@/lib/redis';
import { trackDbQueryPerformance, incrementCacheHit, incrementCacheMiss } from './monitoring';
import { config } from '@/config/app-config';
import { sendEmailAlert } from './email';
import { logger } from '@/lib/logger';

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 */
function getServiceRoleClient() {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. Please ensure SUPABASE_SERVICE_ROLE_KEY is set in your environment variables.');
    }
    return supabaseAdmin;
}

/**
 * A higher-order function to wrap database operations with performance tracking.
 * @param functionName The name of the function to track.
 * @param fn The async function to execute and track.
 * @returns The result of the wrapped function.
 */
async function withPerformanceTracking<T>(
    functionName: string,
    fn: () => Promise<T>
): Promise<T> {
    const startTime = performance.now();
    try {
        return await fn();
    } finally {
        const endTime = performance.now();
        trackDbQueryPerformance(functionName, endTime - startTime);
    }
}

export async function getCompanySettings(companyId: string): Promise<CompanySettings> {
    return withPerformanceTracking('getCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('company_settings')
            .select('*')
            .eq('company_id', companyId)
            .single();
        
        if (error && error.code !== 'PGRST116') { // PGRST116 = 'no rows returned'
            logger.error(`[DB Service] Error fetching company settings for ${companyId}:`, error);
            throw error;
        }

        if (data) {
            return data as CompanySettings;
        }

        // No settings found, so create and return default settings.
        logger.info(`[DB Service] No settings found for company ${companyId}. Creating defaults.`);
        const defaultSettingsData = {
            company_id: companyId,
            dead_stock_days: config.businessLogic.deadStockDays,
            overstock_multiplier: config.businessLogic.overstockMultiplier,
            high_value_threshold: config.businessLogic.highValueThreshold,
            fast_moving_days: config.businessLogic.fastMovingDays,
        };
        
        const { data: newData, error: insertError } = await supabase
            .from('company_settings')
            .upsert(defaultSettingsData) // Use upsert to avoid race conditions
            .select()
            .single();
        
        if (insertError) {
            logger.error(`[DB Service] Failed to insert default settings for company ${companyId}:`, insertError);
            throw insertError;
        }

        return newData as CompanySettings;
    });
}

export async function updateCompanySettings(companyId: string, settings: Partial<Omit<CompanySettings, 'company_id'>>): Promise<CompanySettings> {
    return withPerformanceTracking('updateCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('company_settings')
            .update({ ...settings, updated_at: new Date().toISOString() })
            .eq('company_id', companyId)
            .select()
            .single();
            
        if (error) {
            logger.error(`[DB Service] Error updating settings for ${companyId}:`, error);
            throw error;
        }
        
        // Invalidate cache since business logic has changed
        logger.info(`[Cache Invalidation] Business settings updated. Invalidating relevant caches for company ${companyId}.`);
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        
        return data as CompanySettings;
    });
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const cacheKey = `company:${companyId}:dashboard`;

  if (isRedisEnabled) {
    try {
        const cachedData = await redisClient.get(cacheKey);
        if (cachedData) {
            logger.info(`[Cache] HIT for dashboard metrics: ${cacheKey}`);
            await incrementCacheHit('dashboard');
            return JSON.parse(cachedData);
        }
        logger.info(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
        await incrementCacheMiss('dashboard');
    } catch (error) {
        logger.error(`[Redis] Error getting cache for ${cacheKey}:`, error);
    }
  }

  const startTime = performance.now();
  const supabase = getServiceRoleClient();
  
  // --- Define all queries ---
  const salesPromise = supabase.from('sales').select('id, total_amount').eq('company_id', companyId);
  const customersPromise = supabase.from('customers').select('id', { count: 'exact', head: true }).eq('company_id', companyId);
  const profitPromise = supabase.from('sales_detail').select('profit').eq('company_id', companyId);
  const inventoryValuePromise = supabase.from('inventory_valuation').select('quantity, cost').eq('company_id', companyId);
  const lowStockPromise = supabase.from('fba_inventory').select('*', { count: 'exact', head: true }).eq('company_id', companyId).lt('quantity', 20);

  const salesTrendQuery = `
    SELECT TO_CHAR(sale_date, 'YYYY-MM-DD') as date, SUM(total_amount) as "Sales"
    FROM sales WHERE company_id = '${companyId}' AND sale_date >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY 1 ORDER BY 1 ASC
  `;
  const salesTrendPromise = supabase.rpc('execute_dynamic_query', { query_text: salesTrendQuery.trim().replace(/;/g, '') });
  
  const topCustomersQuery = `
    SELECT c.name, SUM(s.total_amount) as value
    FROM sales s JOIN customers c ON s.customer_id = c.id
    WHERE s.company_id = '${companyId}' AND c.company_id = '${companyId}'
    GROUP BY c.name ORDER BY value DESC LIMIT 5
  `;
  const topCustomersPromise = supabase.rpc('execute_dynamic_query', { query_text: topCustomersQuery.trim().replace(/;/g, '') });
  
  const inventoryByCategoryQuery = `
    SELECT pa.value as name, sum(iv.quantity * iv.cost) as value 
    FROM inventory_valuation iv JOIN product_attributes pa ON iv.sku = pa.sku AND pa.key = 'category'
    WHERE iv.company_id = '${companyId}' AND pa.company_id = '${companyId}'
    GROUP BY pa.value
  `;
  const inventoryByCategoryPromise = supabase.rpc('execute_dynamic_query', { query_text: inventoryByCategoryQuery.trim().replace(/;/g, '') });

  const returnRateQuery = `
    WITH Sales90Days AS (
        SELECT count(id) as total_sales FROM sales
        WHERE company_id = '${companyId}' AND sale_date >= (CURRENT_DATE - INTERVAL '90 days')
    ), Returns90Days AS (
        SELECT count(id) as total_returns FROM returns
        WHERE company_id = '${companyId}' AND return_date >= (CURRENT_DATE - INTERVAL '90 days')
    )
    SELECT
        s.total_sales, r.total_returns,
        CASE WHEN s.total_sales > 0 THEN (r.total_returns::decimal / s.total_sales) * 100 ELSE 0 END as return_rate
    FROM Sales90Days s, Returns90Days r
  `;
  const returnRatePromise = supabase.rpc('execute_dynamic_query', { query_text: returnRateQuery.trim().replace(/;/g, '') });

  // --- Execute all queries in parallel ---
  const results = await Promise.allSettled([
    salesPromise,
    customersPromise,
    profitPromise,
    inventoryValueResult,
    lowStockPromise,
    salesTrendPromise,
    topCustomersPromise,
    inventoryByCategoryPromise,
    returnRatePromise,
  ]);
  
  const endTime = performance.now();
  await trackDbQueryPerformance('getDashboardMetrics', endTime - startTime);
  
  // --- Helper to safely extract data and handle errors ---
  const extractData = (result: PromiseSettledResult<any>, defaultValue: any) => {
    if (result.status === 'fulfilled' && !result.value.error) {
      return result.value.data ?? defaultValue;
    }
    if (result.status === 'rejected' || (result.status === 'fulfilled' && result.value.error)) {
        const error = result.status === 'rejected' ? result.reason : result.value.error;
        if (error?.message && !error.message.includes('does not exist')) { 
            logger.warn(`[DB Service] A dashboard metric query failed:`, error?.message);
        }
    }
    return defaultValue;
  };

  const extractCount = (result: PromiseSettledResult<any>) => {
      if (result.status === 'fulfilled' && !result.value.error) {
          return result.value.count || 0;
      }
      return 0;
  }
  
  // --- Process results ---
  const [
    salesResult,
    customersResult,
    profitResult,
    inventoryValueResult,
    lowStockResult,
    salesTrendResult,
    topCustomersResult,
    inventoryByCategoryResult,
    returnRateResult,
  ] = results;

  const sales = extractData(salesResult, []);
  const customersCount = extractCount(customersResult);
  const profitData = extractData(profitResult, []);
  const inventoryValueData = extractData(inventoryValueResult, []);
  const lowStockItemsCount = extractCount(lowStockResult);

  const salesTrendData = extractData(salesTrendResult, []);
  const topCustomersData = extractData(topCustomersResult, []);
  const inventoryByCategoryData = extractData(inventoryByCategoryResult, []);
  const returnRateData = extractData(returnRateResult, [])[0];

  const totalSalesValue = sales.reduce((sum: number, sale: any) => sum + (sale.total_amount || 0), 0);
  const totalOrders = sales.length;
  const averageOrderValue = totalOrders > 0 ? totalSalesValue / totalOrders : 0;
  const totalProfit = profitData.reduce((sum: number, item: any) => sum + (item.profit || 0), 0);
  const totalInventoryValue = inventoryValueData.reduce((sum: number, item: any) => sum + ((item.quantity || 0) * (item.cost || 0)), 0);
  const returnRate = returnRateData?.return_rate || 0;
  
  const finalMetrics: DashboardMetrics = {
      totalSalesValue: Math.round(totalSalesValue),
      totalProfit: Math.round(totalProfit),
      returnRate: returnRate,
      totalInventoryValue: Math.round(totalInventoryValue),
      lowStockItemsCount,
      totalOrders,
      totalCustomers: customersCount,
      averageOrderValue,
      salesTrendData: salesTrendData || [],
      inventoryByCategoryData: inventoryByCategoryData || [],
      topCustomersData: topCustomersData || [],
  };

  if (isRedisEnabled) {
      try {
          await redisClient.set(cacheKey, JSON.stringify(finalMetrics), 'EX', config.redis.ttl.dashboard);
          logger.info(`[Cache] SET for dashboard metrics: ${cacheKey}`);
      } catch (error) {
          logger.error(`[Redis] Error setting cache for ${cacheKey}:`, error);
      }
  }

  return finalMetrics;
}

export async function getProductsData(companyId: string): Promise<any[]> {
  // With the `products` table removed, this function no longer has a single source of truth.
  // Returning an empty array to prevent errors on pages that used to call this.
  // The AI should be used for specific inventory queries now.
  return Promise.resolve([]);
}

async function getRawDeadStockData(companyId: string, settings: CompanySettings): Promise<DeadStockItem[]> {
    const supabase = getServiceRoleClient();
    const deadStockDays = settings.dead_stock_days;

    const deadStockQuery = `
        WITH LastSale AS (
            SELECT
                oi.sku,
                MAX(s.sale_date) as last_sale_date
            FROM sales s
            JOIN order_items oi ON s.id = oi.sale_id
            WHERE s.company_id = '${companyId}' AND oi.company_id = '${companyId}'
            GROUP BY oi.sku
        )
        SELECT
            iv.sku,
            iv.product_name,
            iv.quantity,
            iv.cost,
            (iv.quantity * iv.cost) as total_value,
            ls.last_sale_date
        FROM inventory_valuation iv
        LEFT JOIN LastSale ls ON iv.sku = ls.sku
        WHERE iv.company_id = '${companyId}'
        AND iv.quantity > 0
        AND (ls.last_sale_date IS NULL OR ls.last_sale_date < CURRENT_DATE - INTERVAL '${deadStockDays} days')
        ORDER BY total_value DESC;
    `;

    const { data, error } = await supabase.rpc('execute_dynamic_query', {
        query_text: deadStockQuery.trim().replace(/;/g, '')
    });

    if (error) {
        logger.error(`[DB Service] Error fetching raw dead stock data for company ${companyId}:`, error);
        // If the query fails (e.g., tables don't exist), return empty array to prevent crashes.
        return [];
    }

    return (data || []) as DeadStockItem[];
}

export async function getDeadStockPageData(companyId: string) {
    return withPerformanceTracking('getDeadStockPageData', async () => {
        const cacheKey = `company:${companyId}:deadstock`;
        if (isRedisEnabled) {
            try {
                const cachedData = await redisClient.get(cacheKey);
                if (cachedData) {
                    await incrementCacheHit('deadstock');
                    return JSON.parse(cachedData);
                }
                await incrementCacheMiss('deadstock');
            } catch(e) { logger.error(`[Redis] Error getting cache for ${cacheKey}`, e); }
        }

        const settings = await getCompanySettings(companyId);
        const deadStockItems = await getRawDeadStockData(companyId, settings);
        
        const totalValue = deadStockItems.reduce((sum, item) => sum + item.total_value, 0);
        const totalUnits = deadStockItems.reduce((sum, item) => sum + item.quantity, 0);

        const result = {
            deadStockItems,
            totalValue,
            totalUnits,
        };

        if (isRedisEnabled) {
        try {
            await redisClient.set(cacheKey, JSON.stringify(result), 'EX', 3600); // 1-hour TTL
        } catch (e) { logger.error(`[Redis] Error setting cache for ${cacheKey}`, e) }
        }

        return result;
    });
}


/**
 * This function directly queries the vendors table to get a list of all suppliers
 * for a given company, ensuring a single, consistent method for data retrieval.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    return withPerformanceTracking('getSuppliersFromDB', async () => {
        const cacheKey = `company:${companyId}:suppliers`;
        if (isRedisEnabled) {
            try {
                const cachedData = await redisClient.get(cacheKey);
                if (cachedData) {
                    await incrementCacheHit('suppliers');
                    return JSON.parse(cachedData);
                }
                await incrementCacheMiss('suppliers');
            } catch (e) { logger.error(`[Redis] Error getting cache for ${cacheKey}`, e) }
        }

        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('vendors')
            .select('id, vendor_name, contact_info, address, terms, account_number')
            .eq('company_id', companyId);
        
        if (error) {
            logger.error('Error fetching suppliers from DB', error);
            throw new Error(`Could not load supplier data: ${error.message}`);
        }
        
        const result = data?.map(v => ({
            id: v.id,
            name: v.vendor_name,
            contact_info: v.contact_info,
            address: v.address,
            terms: v.terms,
            account_number: v.account_number,
        })) || [];

        if (isRedisEnabled) {
        try {
            await redisClient.set(cacheKey, JSON.stringify(result), 'EX', 600); // 10 min TTL
        } catch (e) { logger.error(`[Redis] Error setting cache for ${cacheKey}`, e) }
        }

        return result;
    });
}


export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    return withPerformanceTracking('getAlertsFromDB', async () => {
        const cacheKey = `company:${companyId}:alerts`;
        if (isRedisEnabled) {
            try {
                const cachedData = await redisClient.get(cacheKey);
                if (cachedData) {
                    await incrementCacheHit('alerts');
                    return JSON.parse(cachedData);
                }
                await incrementCacheMiss('alerts');
            } catch(e) { logger.error(`[Redis] Error getting cache for ${cacheKey}`, e); }
        }
        
        const supabase = getServiceRoleClient();
        const settings = await getCompanySettings(companyId);
        const alerts: Alert[] = [];
        
        // --- Low Stock Alerts ---
        // This is a simplified example. A real implementation would be more robust.
        const { data: lowStockItems, error: lowStockError } = await supabase
            .from('fba_inventory') // Assuming reorder point is on this table.
            .select('sku, quantity, product_name')
            .eq('company_id', companyId)
            .lt('quantity', 20); // Using a static 20 for reorder point as an example.

        if (lowStockError) {
            logger.warn('[DB Service] Could not check for low stock items:', lowStockError.message);
        } else if (lowStockItems) {
            for (const item of lowStockItems) {
                const alert: Alert = {
                    id: `low-stock-${item.sku}`,
                    type: 'low_stock',
                    title: `Low Stock Warning`,
                    message: `Item "${item.product_name || item.sku}" is running low on stock.`,
                    severity: 'warning',
                    timestamp: new Date().toISOString(),
                    metadata: {
                        productId: item.sku,
                        productName: item.product_name || item.sku,
                        currentStock: item.quantity,
                        reorderPoint: 20 // Example reorder point
                    },
                };
                alerts.push(alert);
                // await sendEmailAlert(alert);
            }
        }
        
        // --- Dead Stock Alerts ---
        const deadStockItems = await getRawDeadStockData(companyId, settings);
        for (const item of deadStockItems) {
            const alert: Alert = {
                id: `dead-stock-${item.sku}`,
                type: 'dead_stock',
                title: `Dead Stock Alert`,
                message: `Item "${item.product_name || item.sku}" is now considered dead stock.`,
                severity: 'info',
                timestamp: new Date().toISOString(),
                metadata: {
                    productId: item.sku,
                    productName: item.product_name || item.sku,
                    currentStock: item.quantity,
                    lastSoldDate: item.last_sale_date,
                    value: item.total_value,
                },
            };
            alerts.push(alert);
            // await sendEmailAlert(alert);
        }
        
        if (isRedisEnabled) {
            try {
                await redisClient.set(cacheKey, JSON.stringify(alerts), 'EX', 3600);
            } catch (e) { logger.error(`[Redis] Error setting cache for ${cacheKey}`, e); }
        }

        return alerts;
    });
}

// These are the tables we want to expose to the user for querying.
// We are explicitly listing them to match what the AI has been told it can query.
// This list is now updated to reflect the new, more complex schema.
const USER_FACING_TABLES = [
    'vendors', 
    'sales', 
    'sales_detail',
    'customers', 
    'returns', 
    'return_items',
    'order_items', 
    'fba_inventory', 
    'inventory_valuation', 
    'warehouse_locations', 
    'price_lists',
    'product_attributes',
    'daily_stats',
];

/**
 * Fetches the schema and sample data for user-facing tables.
 * @param companyId The ID of the company to fetch data for.
 * @returns An array of objects, each containing a table name and sample rows.
 */
export async function getDatabaseSchemaAndData(companyId: string): Promise<{ tableName: string; rows: any[] }[]> {
    return withPerformanceTracking('getDatabaseSchemaAndData', async () => {
        const supabase = getServiceRoleClient();
        const results: { tableName: string; rows: any[] }[] = [];

        for (const tableName of USER_FACING_TABLES) {
            const { data, error } = await supabase
            .from(tableName)
            .select('*')
            .eq('company_id', companyId)
            .limit(10);

            if (error) {
            logger.warn(`[Database Explorer] Could not fetch data for table '${tableName}'. It might not exist or be configured for the current company. Error: ${error.message}`);
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
    });
}

/**
 * Retrieves the most relevant query patterns for a company to provide as examples to the AI.
 * @param companyId The ID of the company.
 * @param limit The maximum number of patterns to retrieve.
 * @returns A promise that resolves to an array of query patterns.
 */
export async function getQueryPatternsForCompany(
  companyId: string,
  limit = 3
): Promise<{ user_question: string; successful_sql_query: string }[]> {
    return withPerformanceTracking('getQueryPatternsForCompany', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('query_patterns')
            .select('user_question, successful_sql_query')
            .eq('company_id', companyId)
            .order('usage_count', { ascending: false })
            .order('last_used_at', { ascending: false })
            .limit(limit);

        if (error) {
            // This is not a critical error; the system can proceed without these examples.
            logger.warn(`[DB Service] Could not fetch query patterns for company ${companyId}: ${error.message}`);
            return [];
        }

        return data || [];
    });
}

/**
 * Saves a successful query pattern to the database to be used for future learning.
 * This function performs an "upsert" by first checking if a pattern exists.
 * @param companyId The ID of the company.
 * @param userQuestion The user's original question.
 * @param sqlQuery The successful SQL query that was executed.
 */
export async function saveSuccessfulQuery(
  companyId: string,
  userQuestion: string,
  sqlQuery: string
): Promise<void> {
    return withPerformanceTracking('saveSuccessfulQuery', async () => {
        const supabase = getServiceRoleClient();

        // Check if a pattern for this question already exists for this company
        const { data: existingPattern, error: selectError } = await supabase
            .from('query_patterns')
            .select('id, usage_count')
            .eq('company_id', companyId)
            .eq('user_question', userQuestion)
            .single();

        if (selectError && selectError.code !== 'PGRST116') { // Ignore 'no rows' error
            logger.warn(`[DB Service] Could not check for existing query pattern: ${selectError.message}`);
            return;
        }

        if (existingPattern) {
            // If it exists, update the usage count and last used timestamp
            const { error: updateError } = await supabase
                .from('query_patterns')
                .update({
                    usage_count: (existingPattern.usage_count || 0) + 1,
                    last_used_at: new Date().toISOString(),
                    successful_sql_query: sqlQuery // Also update the query in case the AI improved it
                })
                .eq('id', existingPattern.id);

            if (updateError) {
                logger.warn(`[DB Service] Could not update query pattern: ${updateError.message}`);
            } else {
                logger.debug(`[DB Service] Updated query pattern for question: "${userQuestion}"`);
            }
        } else {
            // If it doesn't exist, insert a new record
            const { error: insertError } = await supabase
                .from('query_patterns')
                .insert({
                    company_id: companyId,
                    user_question: userQuestion,
                    successful_sql_query: sqlQuery,
                    usage_count: 1,
                    last_used_at: new Date().toISOString()
                });

            if (insertError) {
                logger.warn(`[DB Service] Could not insert new query pattern: ${insertError.message}`);
            } else {
                logger.info(`[DB Service] Inserted new query pattern for question: "${userQuestion}"`);
            }
        }
    });
}
