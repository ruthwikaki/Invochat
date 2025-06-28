
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
import type { DashboardMetrics, Supplier, Alert, CompanySettings } from '@/types';
import { subDays, differenceInDays, parseISO, isBefore } from 'date-fns';
import { redisClient, isRedisEnabled, invalidateCompanyCache } from '@/lib/redis';
import { trackDbQueryPerformance, incrementCacheHit, incrementCacheMiss } from './monitoring';
import { APP_CONFIG } from '@/config/app-config';
import { sendEmailAlert } from './email';

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 */
function getServiceRoleClient() {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. Please ensure SUPABASE_SERVICE_ROLE_KEY is set in your environment variables.');
    }
    return supabaseAdmin;
}

export async function getCompanySettings(companyId: string): Promise<CompanySettings> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('company_settings')
        .select('*')
        .eq('company_id', companyId)
        .single();
    
    if (error && error.code !== 'PGRST116') { // PGRST116 = 'no rows returned'
        console.error(`[DB Service] Error fetching company settings for ${companyId}:`, error);
        throw error;
    }

    if (data) {
        return data as CompanySettings;
    }

    // No settings found, so create and return default settings.
    console.log(`[DB Service] No settings found for company ${companyId}. Creating defaults.`);
    const defaultSettingsData = {
        company_id: companyId,
        dead_stock_days: APP_CONFIG.businessLogic.deadStockDays,
        overstock_multiplier: APP_CONFIG.businessLogic.overstockMultiplier,
        high_value_threshold: APP_CONFIG.businessLogic.highValueThreshold,
        fast_moving_days: APP_CONFIG.businessLogic.fastMovingDays,
    };
    
    const { data: newData, error: insertError } = await supabase
        .from('company_settings')
        .upsert(defaultSettingsData) // Use upsert to avoid race conditions
        .select()
        .single();
    
    if (insertError) {
        console.error(`[DB Service] Failed to insert default settings for company ${companyId}:`, insertError);
        throw insertError;
    }

    return newData as CompanySettings;
}

export async function updateCompanySettings(companyId: string, settings: Partial<Omit<CompanySettings, 'company_id'>>): Promise<CompanySettings> {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('company_settings')
        .update({ ...settings, updated_at: new Date().toISOString() })
        .eq('company_id', companyId)
        .select()
        .single();
        
    if (error) {
        console.error(`[DB Service] Error updating settings for ${companyId}:`, error);
        throw error;
    }
    
    // Invalidate cache since business logic has changed
    console.log(`[Cache Invalidation] Business settings updated. Invalidating relevant caches for company ${companyId}.`);
    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
    
    return data as CompanySettings;
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const cacheKey = `company:${companyId}:dashboard`;

  if (isRedisEnabled) {
    try {
        const cachedData = await redisClient.get(cacheKey);
        if (cachedData) {
            console.log(`[Cache] HIT for dashboard metrics: ${cacheKey}`);
            await incrementCacheHit('dashboard');
            return JSON.parse(cachedData);
        }
        console.log(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
        await incrementCacheMiss('dashboard');
    } catch (error) {
        console.error(`[Redis] Error getting cache for ${cacheKey}:`, error);
    }
  }

  const startTime = performance.now();
  const supabase = getServiceRoleClient();
  
  // With the `products` table removed, we query other tables.
  const vendorsPromise = supabase.from('vendors').select('*', { count: 'exact', head: true }).eq('company_id', companyId);
  const salesPromise = supabase.from('sales').select('total_amount').eq('company_id', companyId);

  // Queries for charts, executed via a secure RPC function
  const salesTrendQuery = `
    SELECT
      TO_CHAR(sale_date, 'YYYY-MM-DD') as date,
      SUM(total_amount) as "Sales"
    FROM sales
    WHERE company_id = '${companyId}' AND sale_date >= (CURRENT_DATE - INTERVAL '30 days')
    GROUP BY 1
    ORDER BY 1 ASC
  `;
  const salesTrendPromise = supabase.rpc('execute_dynamic_query', { query_text: salesTrendQuery.trim().replace(/;/g, '') });
  
  // Inventory by category is now too complex for a single static query.
  // We will return empty data and let the AI handle this on demand.
  const inventoryByCategoryPromise = Promise.resolve({ data: [], error: null });

  const [
    vendorsRes,
    salesRes,
    salesTrendRes,
    inventoryByCategoryRes
  ] = await Promise.all([
    vendorsPromise,
    salesPromise,
    salesTrendPromise,
    inventoryByCategoryPromise
  ]);

  const endTime = performance.now();
  await trackDbQueryPerformance('getDashboardMetrics', endTime - startTime);

  const { count: suppliersCount, error: suppliersError } = vendorsRes;
  const { data: sales, error: salesError } = salesRes;
  const { data: salesTrendData, error: salesTrendError } = salesTrendRes;
  const { data: inventoryByCategoryData, error: inventoryByCategoryError } = inventoryByCategoryRes;
  
  const firstError = suppliersError || salesError || salesTrendError || inventoryByCategoryError;
  if (firstError) {
    console.error('Dashboard data fetching error:', firstError);
    throw new Error(firstError.message);
  }

  const totalSalesValue = (sales || []).reduce((sum, sale) => sum + (sale.total_amount || 0), 0);

  // Note: Inventory value, SKUs, dead stock, and low stock are now complex calculations.
  // We will return 0 for these and let the AI calculate them on demand.
  const finalMetrics: DashboardMetrics = {
      inventoryValue: 0,
      deadStockValue: 0,
      lowStockCount: 0,
      totalSKUs: 0,
      totalSuppliers: suppliersCount || 0,
      totalSalesValue: Math.round(totalSalesValue),
      salesTrendData: salesTrendData || [],
      inventoryByCategoryData: inventoryByCategoryData || [],
  };

  if (isRedisEnabled) {
      try {
          await redisClient.set(cacheKey, JSON.stringify(finalMetrics), 'EX', 300);
          console.log(`[Cache] SET for dashboard metrics: ${cacheKey}`);
      } catch (error) {
          console.error(`[Redis] Error setting cache for ${cacheKey}:`, error);
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

export async function getDeadStockPageData(companyId: string) {
    // This is now a complex calculation. We will return an empty state
    // and recommend the user ask the AI for this information.
    return { deadStock: [], totalValue: 0, totalUnits: 0, averageAge: 0 };
}

/**
 * This function directly queries the vendors table to get a list of all suppliers
 * for a given company, ensuring a single, consistent method for data retrieval.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    const cacheKey = `company:${companyId}:suppliers`;
    if (isRedisEnabled) {
        try {
            const cachedData = await redisClient.get(cacheKey);
            if (cachedData) {
                await incrementCacheHit('suppliers');
                return JSON.parse(cachedData);
            }
            await incrementCacheMiss('suppliers');
        } catch (e) { console.error(`[Redis] Error getting cache for ${cacheKey}`, e) }
    }

    const startTime = performance.now();
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('vendors')
        .select('id, vendor_name, contact_info, address, terms, account_number')
        .eq('company_id', companyId);
    
    const endTime = performance.now();
    await trackDbQueryPerformance('getSuppliersFromDB', endTime - startTime);

    if (error) {
        console.error('Error fetching suppliers from DB', error);
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
      } catch (e) { console.error(`[Redis] Error setting cache for ${cacheKey}`, e) }
    }

    return result;
}


export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    // Alerting is now a complex, on-demand calculation better suited for the AI.
    // We return an empty array to prevent errors on the Alerts page.
    return [];
}

// These are the tables we want to expose to the user.
// We are explicitly listing them to match what the AI has been told it can query.
const USER_FACING_TABLES = ['vendors', 'sales', 'customers', 'returns', 'order_items', 'fba_inventory', 'inventory_valuation', 'warehouse_locations', 'price_lists'];

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
    console.warn(`[DB Service] Could not fetch query patterns for company ${companyId}: ${error.message}`);
    return [];
  }

  return data || [];
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
    const supabase = getServiceRoleClient();

    // Check if a pattern for this question already exists for this company
    const { data: existingPattern, error: selectError } = await supabase
        .from('query_patterns')
        .select('id, usage_count')
        .eq('company_id', companyId)
        .eq('user_question', userQuestion)
        .single();

    if (selectError && selectError.code !== 'PGRST116') { // Ignore 'no rows' error
        console.warn(`[DB Service] Could not check for existing query pattern: ${selectError.message}`);
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
            console.warn(`[DB Service] Could not update query pattern: ${updateError.message}`);
        } else {
            console.log(`[DB Service] Updated query pattern for question: "${userQuestion}"`);
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
            console.warn(`[DB Service] Could not insert new query pattern: ${insertError.message}`);
        } else {
            console.log(`[DB Service] Inserted new query pattern for question: "${userQuestion}"`);
        }
    }
}
