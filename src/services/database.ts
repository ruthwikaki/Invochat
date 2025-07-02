'use server';

/**
 * @fileoverview
 * This file is the single source of truth for all direct database queries.
 * It uses the Supabase Admin client (service_role) to bypass Row Level Security (RLS).
 * SECURITY: All functions in this file MUST manually filter queries by `companyId`.
 */

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { DashboardMetrics, Alert, CompanySettings, UnifiedInventoryItem, User, TeamMember, Anomaly, PurchaseOrder, PurchaseOrderCreateInput, PurchaseOrderUpdateInput, ReorderSuggestion, ReceiveItemsFormInput, ChannelFee, Location, LocationFormData, SupplierFormData, Supplier, InventoryUpdateData, SupplierPerformanceReport, InventoryLedgerEntry } from '@/types';
import { CompanySettingsSchema, DeadStockItemSchema, SupplierSchema, AnomalySchema, PurchaseOrderSchema, ReorderSuggestionSchema, ChannelFeeSchema, LocationSchema, LocationFormSchema, SupplierFormSchema, InventoryUpdateSchema, InventoryLedgerEntrySchema } from '@/types';
import { redisClient, isRedisEnabled, invalidateCompanyCache } from '@/lib/redis';
import { trackDbQueryPerformance, incrementCacheHit, incrementCacheMiss } from './monitoring';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { PurchaseOrderCreateSchema } from '@/types';
import { redirect } from 'next/navigation';
import type { Integration } from '@/features/integrations/types';

// Simple regex to validate a string is in UUID format.
const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const isValidUuid = (uuid: string) => UUID_REGEX.test(uuid);

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

export async function refreshMaterializedViews(companyId: string): Promise<void> {
    if (!isValidUuid(companyId)) return;
    await withPerformanceTracking('refreshMaterializedViews', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('refresh_dashboard_metrics');
        if (error) {
            logError(error, { context: `Failed to refresh materialized views for company ${companyId}` });
            // Don't throw, as this is a background optimization, not a critical failure
        } else {
            logger.info(`[DB Service] Refreshed materialized views for company ${companyId}`);
        }
    });
}

export async function getSettings(companyId: string): Promise<CompanySettings> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    
    return withPerformanceTracking('getCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('company_settings')
            .select('*')
            .eq('company_id', companyId)
            .single();
        
        if (error && error.code !== 'PGRST116') {
            logError(error, { context: `Error fetching company settings for ${companyId}` });
            throw error;
        }

        if (data) {
            // Validate data against the Zod schema before returning
            return CompanySettingsSchema.parse(data);
        }

        logger.info(`[DB Service] No settings found for company ${companyId}. Creating defaults.`);
        const defaultSettingsData = {
            company_id: companyId,
            dead_stock_days: config.businessLogic.deadStockDays,
            overstock_multiplier: config.businessLogic.overstockMultiplier,
            high_value_threshold: config.businessLogic.highValueThreshold,
            fast_moving_days: config.businessLogic.fastMovingDays,
            currency: 'USD',
            timezone: 'UTC',
            tax_rate: 0,
            theme_primary_color: '256 75% 61%',
            theme_background_color: '222 83% 4%',
            theme_accent_color: '217 33% 17%',
            custom_rules: {},
        };
        
        const { data: newData, error: insertError } = await supabase
            .from('company_settings')
            .upsert(defaultSettingsData)
            .select()
            .single();
        
        if (insertError) {
            logError(insertError, { context: `Failed to insert default settings for company ${companyId}` });
            throw insertError;
        }

        return CompanySettingsSchema.parse(newData);
    });
}

const CompanySettingsUpdateSchema = z.object({
    dead_stock_days: z.coerce.number().int().positive('Dead stock days must be a positive number.').optional(),
    fast_moving_days: z.coerce.number().int().positive('Fast-moving days must be a positive number.').optional(),
    overstock_multiplier: z.coerce.number().positive('Overstock multiplier must be a positive number.').optional(),
    high_value_threshold: z.coerce.number().int().positive('High-value threshold must be a positive number.').optional(),
    theme_primary_color: z.string().nullable().optional(),
    theme_background_color: z.string().nullable().optional(),
    theme_accent_color: z.string().nullable().optional(),
});


export async function updateSettingsInDb(companyId: string, settings: Partial<CompanySettings>): Promise<CompanySettings> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');

    const parsedSettings = CompanySettingsUpdateSchema.partial().safeParse(settings);
    
    if (!parsedSettings.success) {
        const errorMessages = parsedSettings.error.issues.map(issue => issue.message).join(' ');
        throw new Error(`Invalid settings format: ${errorMessages}`);
    }

    return withPerformanceTracking('updateCompanySettings', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase
            .from('company_settings')
            .update({ ...parsedSettings.data, updated_at: new Date().toISOString() })
            .eq('company_id', companyId)
            .select()
            .single();
            
        if (error) {
            logError(error, { context: `Error updating settings for ${companyId}` });
            throw error;
        }
        
        logger.info(`[Cache Invalidation] Business settings updated. Invalidating relevant caches for company ${companyId}.`);
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        
        return CompanySettingsSchema.parse(data);
    });
}

function getIntervalFromRange(dateRange: string): number {
    const days = parseInt(dateRange.replace('d', ''), 10);
    return isNaN(days) ? 30 : days;
}

export async function getDashboardMetrics(companyId: string, dateRange: string = '30d'): Promise<DashboardMetrics> {
  if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
  const cacheKey = `company:${companyId}:dashboard:${dateRange}`;
  const days = getIntervalFromRange(dateRange);

  const fetchAndCacheMetrics = async (): Promise<DashboardMetrics> => {
    return withPerformanceTracking('getDashboardMetricsOptimized', async () => {
        const supabase = getServiceRoleClient();
        
        const { data: mvData, error: mvError } = await supabase
            .from('company_dashboard_metrics')
            .select('inventory_value, low_stock_count, total_skus')
            .eq('company_id', companyId)
            .single();

        if (mvError) logError(mvError, { context: `Could not fetch from materialized view for company ${companyId}` });
        
        const { data: rpcData, error: rpcError } = await supabase.rpc('get_dashboard_metrics', {
            p_company_id: companyId,
            p_days: days,
        });
        
        if (rpcError) {
            logError(rpcError, { context: `Dashboard RPC failed for company ${companyId}` });
            throw rpcError;
        }

        const metrics = rpcData || {};
        const { data: customers } = await supabase.from('customers').select('id', { count: 'exact', head: true }).eq('company_id', companyId);

        const finalMetrics: DashboardMetrics = {
            totalSalesValue: Math.round(metrics.totalSalesValue || 0),
            totalProfit: Math.round(metrics.totalProfit || 0),
            returnRate: metrics.returnRate || 0,
            totalInventoryValue: Math.round(mvData?.inventory_value || 0),
            lowStockItemsCount: mvData?.low_stock_count || 0,
            deadStockItemsCount: metrics.deadStockItemsCount || 0,
            totalSkus: mvData?.total_skus || 0,
            totalOrders: metrics.totalOrders || 0,
            totalCustomers: customers?.count || 0,
            averageOrderValue: metrics.averageOrderValue || 0,
            salesTrendData: (metrics.salesTrendData as { date: string; Sales: number }[]) || [],
            inventoryByCategoryData: (metrics.inventoryByCategoryData as { name: string; value: number }[]) || [],
            topCustomersData: (metrics.topCustomersData as { name: string; value: number }[]) || [],
        };
        
        if (isRedisEnabled) {
            try {
                await redisClient.set(cacheKey, JSON.stringify(finalMetrics), 'EX', config.redis.ttl.dashboard);
                logger.info(`[Cache] SET for dashboard metrics: ${cacheKey}`);
            } catch (error) {
                logError(error, { context: `Redis error setting cache for ${cacheKey}` });
            }
        }
        return finalMetrics;
    });
  };

  if (isRedisEnabled) {
    try {
      const cachedData = await redisClient.get(cacheKey);
      if (cachedData) {
        logger.info(`[Cache] HIT (Stale-While-Revalidate) for dashboard metrics: ${cacheKey}`);
        await incrementCacheHit('dashboard');
        fetchAndCacheMetrics().catch(err => {
            logError(err, { context: `SWR Background Revalidation failed for ${cacheKey}` });
        });
        return JSON.parse(cachedData);
      }
      logger.info(`[Cache] MISS for dashboard metrics: ${cacheKey}`);
      await incrementCacheMiss('dashboard');
    } catch (error) {
        logError(error, { context: `Redis error getting cache for ${cacheKey}` });
    }
  }
  return fetchAndCacheMetrics();
}

async function getRawDeadStockData(companyId: string, settings: CompanySettings) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    const supabase = getServiceRoleClient();
    const deadStockDays = settings.dead_stock_days;

    const deadStockQuery = `
        SELECT
            i.sku,
            i.name as product_name,
            i.quantity,
            i.cost,
            (i.quantity * i.cost) as total_value,
            i.last_sold_date
        FROM inventory i
        WHERE i.company_id = '${companyId}'
        AND i.quantity > 0
        AND (i.last_sold_date IS NULL OR i.last_sold_date < CURRENT_DATE - INTERVAL '${deadStockDays} days')
        ORDER BY total_value DESC;
    `;

    const { data, error } = await supabase.rpc('execute_dynamic_query', {
        query_text: deadStockQuery.trim().replace(/;/g, '')
    });

    if (error) {
        logError(error, { context: `Error fetching raw dead stock data for company ${companyId}` });
        return [];
    }
    
    const result = z.array(DeadStockItemSchema.partial()).safeParse(data || []);
    if (!result.success) {
        logError(result.error, {context: 'Zod parsing error for dead stock data'});
        return [];
    }

    return result.data as DeadStockItem[];
}

export async function getDeadStockPageData(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
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
            } catch(e) { logError(e, { context: `Redis error getting cache for ${cacheKey}` }); }
        }

        const settings = await getSettings(companyId);
        const deadStockItems = await getRawDeadStockData(companyId, settings);
        
        const totalValue = deadStockItems.reduce((sum, item) => sum + (item.total_value || 0), 0);
        const totalUnits = deadStockItems.reduce((sum, item) => sum + (item.quantity || 0), 0);

        const result = {
            deadStockItems,
            totalValue,
            totalUnits,
        };

        if (isRedisEnabled) {
        try {
            await redisClient.set(cacheKey, JSON.stringify(result), 'EX', 3600);
        } catch (e) { logError(e, { context: `Redis error setting cache for ${cacheKey}` }); }
        }

        return result;
    });
}

export async function getSuppliersFromDB(companyId: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getSuppliersFromDB', async () => {
        const cacheKey = `company:${companyId}:suppliers`;
        if (isRedisEnabled) {
            try {
                const cachedData = await redisClient.get(cacheKey);
                if (cachedData) {
                    await incrementCacheHit('suppliers');
                    const parsedData = z.array(SupplierSchema).safeParse(JSON.parse(cachedData));
                    if (parsedData.success) return parsedData.data;
                }
                await incrementCacheMiss('suppliers');
            } catch (e) { logError(e, { context: `Redis error getting cache for ${cacheKey}` }); }
        }

        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('vendors')
            .select('*')
            .eq('company_id', companyId);
        
        if (error) {
            logError(error, { context: 'Error fetching suppliers from DB' });
            throw new Error(`Could not load supplier data: ${error.message}`);
        }
        
        const result = z.array(SupplierSchema).parse(data || []);

        if (isRedisEnabled) {
        try {
            await redisClient.set(cacheKey, JSON.stringify(result), 'EX', 600);
        } catch (e) { logError(e, { context: `Redis error setting cache for ${cacheKey}` }); }
        }

        return result;
    });
}

export async function getPurchaseOrdersFromDB(companyId: string): Promise<PurchaseOrder[]> {
     if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
     return withPerformanceTracking('getPurchaseOrdersFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        const query = `
            SELECT 
                po.*,
                v.vendor_name as supplier_name
            FROM purchase_orders po
            LEFT JOIN vendors v ON po.supplier_id = v.id
            WHERE po.company_id = '${companyId}'
            ORDER BY po.order_date DESC;
        `;

        const { data, error } = await supabase.rpc('execute_dynamic_query', {
            query_text: query.trim().replace(/;/g, '')
        });

        if (error) {
            logError(error, { context: 'Error fetching purchase orders from DB' });
            throw new Error(`Could not load purchase order data: ${error.message}`);
        }

        return z.array(PurchaseOrderSchema.partial()).parse(data || []);
     });
}

export async function getPurchaseOrderByIdFromDB(poId: string, companyId: string): Promise<PurchaseOrder | null> {
    if (!isValidUuid(poId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getPurchaseOrderByIdFromDB', async () => {
        const supabase = getServiceRoleClient();
        const query = `
            SELECT 
                po.*,
                v.vendor_name as supplier_name,
                v.contact_info as supplier_email,
                (
                    SELECT json_agg(
                        json_build_object(
                            'id', poi.id,
                            'po_id', poi.po_id,
                            'sku', poi.sku,
                            'product_name', i.name,
                            'quantity_ordered', poi.quantity_ordered,
                            'quantity_received', poi.quantity_received,
                            'unit_cost', poi.unit_cost,
                            'tax_rate', poi.tax_rate
                        )
                    )
                    FROM purchase_order_items poi
                    JOIN inventory i ON poi.sku = i.sku AND i.company_id = po.company_id
                    WHERE poi.po_id = po.id
                ) as items
            FROM purchase_orders po
            LEFT JOIN vendors v ON po.supplier_id = v.id
            WHERE po.id = '${poId}' AND po.company_id = '${companyId}';
        `;
        
        const { data, error } = await supabase.rpc('execute_dynamic_query', {
            query_text: query.trim().replace(/;/g, '')
        });

        if (error) {
            logError(error, { context: `Error fetching PO ${poId}` });
            throw new Error(`Could not load purchase order data: ${error.message}`);
        }

        if (!data || data.length === 0) {
            return null;
        }

        return PurchaseOrderSchema.parse(data[0]);
    });
}

export async function createPurchaseOrderInDb(companyId: string, poData: PurchaseOrderCreateInput): Promise<PurchaseOrder> {
    return withPerformanceTracking('createPurchaseOrderInDb', async () => {
        const supabase = getServiceRoleClient();
        
        const totalAmount = poData.items.reduce((sum, item) => sum + (item.quantity_ordered * item.unit_cost), 0);
        
        const itemsForRpc = poData.items.map(item => ({
            sku: item.sku,
            quantity_ordered: item.quantity_ordered,
            unit_cost: item.unit_cost,
        }));

        const { data: newPo, error: poError } = await supabase.rpc('create_purchase_order_and_update_inventory', {
            p_company_id: companyId,
            p_supplier_id: poData.supplier_id,
            p_po_number: poData.po_number,
            p_order_date: poData.order_date.toISOString(),
            p_expected_date: poData.expected_date?.toISOString(),
            p_notes: poData.notes,
            p_total_amount: totalAmount,
            p_items: itemsForRpc,
        }).select().single();

        if (poError) {
            logError(poError, { context: 'Failed to execute create_purchase_order_and_update_inventory RPC' });
            throw poError;
        }

        logger.info(`[DB Service] Successfully created PO ${newPo.po_number} and updated on-order quantities.`);

        await invalidateCompanyCache(companyId, ['dashboard']);
        return { ...newPo, items: poData.items };
    });
}


export async function updatePurchaseOrderInDb(poId: string, companyId: string, poData: PurchaseOrderUpdateInput): Promise<void> {
    return withPerformanceTracking('updatePurchaseOrderInDb', async () => {
        const supabase = getServiceRoleClient();
        
        const itemsForRpc = poData.items.map(item => ({
            sku: item.sku,
            quantity_ordered: item.quantity_ordered,
            unit_cost: item.unit_cost,
        }));

        const { error } = await supabase.rpc('update_purchase_order', {
            p_po_id: poId,
            p_company_id: companyId,
            p_supplier_id: poData.supplier_id,
            p_po_number: poData.po_number,
            p_status: poData.status,
            p_order_date: poData.order_date.toISOString(),
            p_expected_date: poData.expected_date?.toISOString(),
            p_notes: poData.notes,
            p_items: itemsForRpc,
        });

        if (error) {
            logError(error, { context: `Failed to update PO ${poId}` });
            throw error;
        }

        logger.info(`[DB Service] Successfully updated PO ${poData.po_number}.`);
        await invalidateCompanyCache(companyId, ['dashboard']);
    });
}

export async function deletePurchaseOrderFromDb(poId: string, companyId: string): Promise<void> {
    return withPerformanceTracking('deletePurchaseOrderFromDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('delete_purchase_order', {
            p_po_id: poId,
            p_company_id: companyId,
        });

        if (error) {
            logError(error, { context: `Failed to delete PO ${poId}` });
            throw error;
        }
        logger.info(`[DB Service] Successfully deleted PO ${poId}.`);
        await invalidateCompanyCache(companyId, ['dashboard']);
    });
}

export async function receivePurchaseOrderItemsInDB(
    poId: string,
    companyId: string,
    items: ReceiveItemsFormInput['items']
): Promise<void> {
    if (!isValidUuid(poId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('receivePurchaseOrderItemsInDB', async () => {
        const supabase = getServiceRoleClient();
        
        const itemsToReceive = items
            .filter(item => item.quantity_to_receive > 0)
            .map(item => ({
                sku: item.sku,
                quantity_to_receive: item.quantity_to_receive
            }));

        if (itemsToReceive.length === 0) {
            throw new Error("No items were marked for receiving.");
        }

        const { error } = await supabase.rpc('receive_purchase_order_items', {
            p_po_id: poId,
            p_items_to_receive: itemsToReceive,
            p_company_id: companyId
        });

        if (error) {
            logError(error, { context: `Failed to receive items for PO ${poId}` });
            throw error;
        }

        logger.info(`[DB Service] Successfully received items for PO ${poId}.`);
        await refreshMaterializedViews(companyId);
        revalidatePath(`/purchase-orders/${poId}`);
        revalidatePath('/inventory');
    });
}


export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
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
            } catch(e) { logError(e, { context: `Redis error getting cache for ${cacheKey}` }); }
        }
        
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_alerts', { p_company_id: companyId });

        if (error) {
            logError(error, { context: 'getAlerts RPC failed' });
            throw error;
        }
        
        const alerts: Alert[] = [];
        for (const item of (data as any[])) {
            if (item.type === 'low_stock') {
                alerts.push({
                    id: `low-stock-${item.sku}`, type: 'low_stock', title: `Low Stock Warning`,
                    message: `Item "${item.product_name || item.sku}" is running low on stock.`,
                    severity: 'warning', timestamp: new Date().toISOString(),
                    metadata: { productId: item.sku, productName: item.product_name || item.sku, currentStock: item.current_stock, reorderPoint: item.reorder_point },
                });
            } else if (item.type === 'dead_stock') {
                alerts.push({
                    id: `dead-stock-${item.sku}`, type: 'dead_stock', title: `Dead Stock Alert`,
                    message: `Item "${item.product_name || item.sku}" is now considered dead stock.`,
                    severity: 'info', timestamp: new Date().toISOString(),
                    metadata: { productId: item.sku, productName: item.product_name || item.sku, currentStock: item.current_stock, lastSoldDate: item.last_sold_date, value: item.value },
                });
            } else if (item.type === 'predictive') {
                alerts.push({
                    id: `predictive-${item.sku}`, type: 'predictive', title: `Predictive Stockout Alert`,
                    message: `You are forecast to run out of stock for "${item.product_name || item.sku}" in approximately ${Math.round(item.days_of_stock_remaining)} days.`,
                    severity: 'warning', timestamp: new Date().toISOString(),
                    metadata: { productId: item.sku, productName: item.product_name || item.sku, currentStock: item.current_stock, daysOfStockRemaining: item.days_of_stock_remaining },
                });
            }
        }
        
        if (isRedisEnabled) {
            try {
                await redisClient.set(cacheKey, JSON.stringify(alerts), 'EX', 3600);
            } catch (e) { logError(e, { context: `Redis error setting cache for ${cacheKey}` }); }
        }

        return alerts;
    });
}

const USER_FACING_TABLES = [
    'vendors', 
    'orders', 
    'customers', 
    'inventory',
    'purchase_orders',
    'purchase_order_items'
];

export async function getDbSchemaAndData(companyId: string): Promise<{ tableName: string; rows: unknown[] }[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');

    return withPerformanceTracking('getDatabaseSchemaAndData', async () => {
        const supabase = getServiceRoleClient();

        // Fetch data for all main tables in parallel
        const tablePromises = USER_FACING_TABLES
            .filter(tableName => tableName !== 'purchase_order_items') // Handle this one separately
            .map(async (tableName) => {
                const { data, error } = await supabase
                    .from(tableName)
                    .select('*')
                    .eq('company_id', companyId)
                    .limit(10);
                
                if (error) {
                    if (!error.message.includes("does not exist")) {
                        logError(error, { context: `Could not fetch data for table '${tableName}'` });
                    }
                    return { tableName, rows: [] };
                }
                return { tableName, rows: data || [] };
            });

        const allTableData = await Promise.all(tablePromises);

        // Now that we have the purchase orders, fetch their related items
        const purchaseOrders = allTableData.find(d => d.tableName === 'purchase_orders')?.rows as PurchaseOrder[] || [];
        const poIds = purchaseOrders.map(po => po.id).filter(Boolean);

        let poItems: unknown[] = [];
        if (poIds.length > 0) {
            const { data, error } = await supabase
                .from('purchase_order_items')
                .select('*')
                .in('po_id', poIds)
                .limit(10);

            if (error) {
                logError(error, { context: `Could not fetch data for table 'purchase_order_items'` });
            } else {
                poItems = data || [];
            }
        }
        allTableData.push({ tableName: 'purchase_order_items', rows: poItems });

        // Ensure the final array is in the original, intended order
        return USER_FACING_TABLES.map(tableName => 
            allTableData.find(d => d.tableName === tableName) || { tableName, rows: [] }
        );
    });
}


export async function getQueryPatternsForCompany(
  companyId: string,
  limit = 3
): Promise<{ user_question: string; successful_sql_query: string }[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
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
            logError(error, { context: `Could not fetch query patterns for company ${companyId}` });
            return [];
        }

        return data || [];
    });
}

export async function saveSuccessfulQuery(
  companyId: string,
  userQuestion: string,
  sqlQuery: string
): Promise<void> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('saveSuccessfulQuery', async () => {
        const supabase = getServiceRoleClient();

        const { data: existingPattern, error: selectError } = await supabase
            .from('query_patterns')
            .select('id, usage_count')
            .eq('company_id', companyId)
            .eq('user_question', userQuestion)
            .single();

        if (selectError && selectError.code !== 'PGRST116') {
            logError(selectError, { context: 'Could not check for existing query pattern' });
            return;
        }

        if (existingPattern) {
            const { error: updateError } = await supabase
                .from('query_patterns')
                .update({
                    usage_count: (existingPattern.usage_count || 0) + 1,
                    last_used_at: new Date().toISOString(),
                    successful_sql_query: sqlQuery
                })
                .eq('id', existingPattern.id);

            if (updateError) {
                logError(updateError, { context: 'Could not update query pattern' });
            } else {
                logger.debug(`[DB Service] Updated query pattern for question: "${userQuestion}"`);
            }
        } else {
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
                logError(insertError, { context: 'Could not insert new query pattern' });
            } else {
                logger.info(`[DB Service] Inserted new query pattern for question: "${userQuestion}"`);
            }
        }
    });
}


export async function getAnomalyInsightsFromDB(companyId: string): Promise<Anomaly[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('generateAnomalyInsights', async () => {
        const supabase = getServiceRoleClient();
        const anomalyQuery = `
            WITH daily_metrics AS (
                SELECT DATE(sale_date) as date,
                    SUM(total_amount) as daily_revenue,
                    COUNT(DISTINCT customer_id) as daily_customers
                FROM orders
                WHERE company_id = '${companyId}'
                AND sale_date >= CURRENT_DATE - INTERVAL '30 days'
                GROUP BY DATE(sale_date)
            ),
            statistics AS (
                SELECT AVG(daily_revenue) as avg_revenue,
                    STDDEV(daily_revenue) as stddev_revenue,
                    AVG(daily_customers) as avg_customers,
                    STDDEV(daily_customers) as stddev_customers
                FROM daily_metrics
            ),
            SELECT
                d.date,
                d.daily_revenue,
                d.daily_customers,
                s.avg_revenue,
                s.avg_customers,
                CASE
                    WHEN ABS(d.daily_revenue - s.avg_revenue) > (2 * s.stddev_revenue)
                    THEN 'Revenue Anomaly'
                    WHEN ABS(d.daily_customers - s.avg_customers) > (2 * s.stddev_customers)
                    THEN 'Customer Count Anomaly'
                    ELSE NULL
                END as anomaly_type
            FROM daily_metrics d, statistics s
            WHERE (s.stddev_revenue > 0 OR s.stddev_customers > 0) AND (
                (s.stddev_revenue > 0 AND ABS(d.daily_revenue - s.avg_revenue) > (2 * s.stddev_revenue))
                OR
                (s.stddev_customers > 0 AND ABS(d.daily_customers - s.avg_customers) > (2 * s.stddev_customers))
            );
        `;

        const { data, error } = await supabase.rpc('execute_dynamic_query', {
            query_text: anomalyQuery.trim().replace(/;/g, '')
        });

        if (error) {
            logError(error, { context: `Error generating anomaly insights for company ${companyId}` });
            throw new Error(`Failed to generate anomaly insights: ${error.message}`);
        }

        return z.array(AnomalySchema).parse(data || []);
    });
}

export async function getInventoryCategoriesFromDB(companyId: string): Promise<string[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getInventoryCategoriesFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        const query = `
            SELECT DISTINCT category FROM inventory
            WHERE company_id = '${companyId}' AND category IS NOT NULL
            ORDER BY category ASC;
        `;

        const { data, error } = await supabase.rpc('execute_dynamic_query', {
            query_text: query.trim().replace(/;/g, '')
        });

        if (error) {
            logError(error, { context: `Error fetching inventory categories for company ${companyId}` });
            return [];
        }
        
        return data.map((item: { category: string }) => item.category) || [];
    });
}

export async function getTeamMembersFromDB(companyId: string): Promise<TeamMember[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getTeamMembersFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('users')
            .select('id, email, role')
            .eq('company_id', companyId);

        if (error) {
            logError(error, { context: `Error fetching team members for company ${companyId}` });
            throw error;
        }
        return data as TeamMember[];
    });
}

export async function inviteUserToCompanyInDb(companyId: string, companyName: string, email: string) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('inviteUserToCompany', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.auth.admin.inviteUserByEmail(email, {
            data: {
                company_id: companyId,
                company_name: companyName,
            },
            redirectTo: `${config.app.url}/dashboard`,
        });

        if (error) {
            logError(error, { context: `Error inviting user ${email} to company ${companyId}` });
            if (error.message.includes('User already exists')) {
                throw new Error('This user already exists in the system. They cannot be invited again.');
            }
            if (error.message.includes('already been invited')) {
                throw new Error('This user has already been invited. They need to accept the existing invitation from their email.');
            }
            throw error;
        }

        return data;
    });
}

export async function removeTeamMemberFromDb(
    userIdToRemove: string,
    companyId: string
): Promise<{ success: boolean; error?: string }> {
    if (!isValidUuid(userIdToRemove) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('removeTeamMemberFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        const { error: adminError } = await supabase.auth.admin.deleteUser(userIdToRemove);

        if (adminError) {
             if (adminError.message.includes('User not found')) {
                 return { success: false, error: "The user could not be found. They may have already been removed." };
            }
            throw new Error(adminError.message);
        }

        return { success: true };
    });
}

export async function updateTeamMemberRoleInDb(
    memberIdToUpdate: string,
    companyId: string,
    newRole: 'Admin' | 'Member'
): Promise<{ success: boolean; error?: string }> {
     if (!isValidUuid(memberIdToUpdate) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
     return withPerformanceTracking('updateTeamMemberRoleInDb', async () => {
        const supabase = getServiceRoleClient();
        
        // You can't change the role of the Owner
        const { data: memberData } = await supabase.from('users').select('role').eq('id', memberIdToUpdate).single();
        if (memberData?.role === 'Owner') {
            return { success: false, error: "The Company Owner's role cannot be changed." };
        }

        const { error: updateError } = await supabase
            .from('users')
            .update({ role: newRole })
            .eq('id', memberIdToUpdate)
            .eq('company_id', companyId);

        if (updateError) {
            logError(updateError, { context: `Failed to update role for ${memberIdToUpdate}` });
            return { success: false, error: updateError.message };
        }
        
        // Also update the role in auth.users for the JWT
        const { error: authUpdateError } = await supabase.auth.admin.updateUserById(memberIdToUpdate, {
            app_metadata: { role: newRole }
        });

        if (authUpdateError) {
            logError(authUpdateError, { context: `Failed to update auth role for ${memberIdToUpdate}` });
            // This is a problem, but the primary DB is updated. We'll log it but not fail the whole op.
        }

        return { success: true };
    });
}


export async function getReorderSuggestionsFromDB(companyId: string): Promise<ReorderSuggestion[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getReorderSuggestionsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const settings = await getSettings(companyId);

        const query = `
            WITH sales_velocity AS (
                SELECT 
                    oi.sku,
                    SUM(oi.quantity)::float / GREATEST(${settings.fast_moving_days}, 1) as daily_sales_velocity
                FROM order_items oi
                JOIN orders o ON oi.sale_id = o.id
                WHERE o.company_id = '${companyId}'
                  AND o.sale_date >= CURRENT_DATE - INTERVAL '${settings.fast_moving_days} days'
                GROUP BY oi.sku
            ),
            ranked_suppliers AS (
                SELECT 
                    sc.sku,
                    v.vendor_name,
                    sc.supplier_id,
                    sc.unit_cost,
                    ROW_NUMBER() OVER(PARTITION BY sc.sku ORDER BY sc.unit_cost ASC) as rn
                FROM supplier_catalogs sc
                JOIN vendors v ON sc.supplier_id = v.id
                WHERE v.company_id = '${companyId}'
            ),
            best_supplier AS (
                SELECT sku, vendor_name as supplier_name, supplier_id, unit_cost
                FROM ranked_suppliers
                WHERE rn = 1
            ),
            reorder_points AS (
                SELECT
                    i.sku,
                    i.name as product_name,
                    i.quantity as current_quantity,
                    COALESCE(rr.min_stock, i.reorder_point, 0) as reorder_point,
                    COALESCE(
                        rr.max_stock - i.quantity, 
                        rr.reorder_quantity, 
                        ceil(COALESCE(sv.daily_sales_velocity, 0) * 30)
                    ) as suggested_reorder_quantity,
                    bs.supplier_name,
                    bs.supplier_id,
                    bs.unit_cost
                FROM inventory i
                LEFT JOIN reorder_rules rr ON i.sku = rr.sku AND i.company_id = rr.company_id
                LEFT JOIN sales_velocity sv ON i.sku = sv.sku
                LEFT JOIN best_supplier bs ON i.sku = bs.sku
                WHERE i.company_id = '${companyId}'
            )
            SELECT *
            FROM reorder_points
            WHERE current_quantity < reorder_point
            AND suggested_reorder_quantity > 0;
        `;
        
        const { data, error } = await supabase.rpc('execute_dynamic_query', {
            query_text: query.trim().replace(/;/g, '')
        });
        
        if (error) {
            logError(error, { context: `Error getting reorder suggestions for company ${companyId}` });
            throw new Error(`Could not generate reorder suggestions: ${error.message}`);
        }

        const parsedData = z.array(ReorderSuggestionSchema).safeParse(data || []);
        if (!parsedData.success) {
            logError(parsedData.error, { context: 'Zod parsing error for reorder suggestions' });
            return [];
        }
        return parsedData.data;
    });
}

export async function getHistoricalSalesForSkus(
    companyId: string, 
    skus: string[]
): Promise<{ sku: string; monthly_sales: { month: string; total_quantity: number }[] }[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    if (skus.length === 0) return [];

    return withPerformanceTracking('getHistoricalSalesForSkus', async () => {
        const supabase = getServiceRoleClient();

        // Use the new, secure RPC function
        const { data, error } = await supabase.rpc('get_historical_sales', {
            p_company_id: companyId,
            p_skus: skus
        });
        
        if (error) {
            logError(error, { context: `Error fetching historical sales for SKUs in company ${companyId}` });
            throw error;
        }

        return data || [];
    });
}

export async function getChannelFeesFromDB(companyId: string): Promise<ChannelFee[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getChannelFeesFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('channel_fees')
            .select('*')
            .eq('company_id', companyId)
            .order('channel_name');

        if (error) {
            logError(error, { context: `Error fetching channel fees for company ${companyId}` });
            throw error;
        }
        return z.array(ChannelFeeSchema).parse(data || []);
    });
}

export async function upsertChannelFeeInDB(companyId: string, fee: { channel_name: string; percentage_fee: number; fixed_fee: number; }): Promise<ChannelFee> {
     if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
     return withPerformanceTracking('upsertChannelFeeInDB', async () => {
        const supabase = getServiceRoleClient();
        
        const upsertData = {
            company_id: companyId,
            channel_name: fee.channel_name,
            percentage_fee: fee.percentage_fee,
            fixed_fee: fee.fixed_fee,
            updated_at: new Date().toISOString(),
        };

        const { data, error } = await supabase
            .from('channel_fees')
            .upsert(upsertData, { onConflict: 'company_id, channel_name' })
            .select()
            .single();

        if (error) {
            logError(error, { context: 'Failed to upsert channel fee' });
            throw error;
        }

        revalidatePath('/settings');
        return ChannelFeeSchema.parse(data);
    });
}

// Location DB Functions
export async function getLocationsFromDB(companyId: string): Promise<Location[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getLocationsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('locations')
            .select('*')
            .eq('company_id', companyId)
            .order('name');
        if (error) {
            logError(error, { context: 'getLocationsFromDB' });
            throw error;
        }
        return z.array(LocationSchema).parse(data || []);
    });
}

export async function getLocationByIdFromDB(id: string, companyId: string): Promise<Location | null> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getLocationByIdFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('locations')
            .select('*')
            .eq('id', id)
            .eq('company_id', companyId)
            .maybeSingle();
        if (error) {
            logError(error, { context: `getLocationByIdFromDB: ${id}` });
            throw error;
        }
        return data ? LocationSchema.parse(data) : null;
    });
}

export async function createLocationInDB(companyId: string, locationData: LocationFormData): Promise<Location> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('createLocationInDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('locations')
            .insert({ ...locationData, company_id: companyId })
            .select()
            .single();
        if (error) {
            logError(error, { context: 'createLocationInDB' });
            if (error.code === '23505') throw new Error('A location with this name already exists.');
            throw error;
        }
        return LocationSchema.parse(data);
    });
}

export async function updateLocationInDB(id: string, companyId: string, locationData: LocationFormData): Promise<Location> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('updateLocationInDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('locations')
            .update(locationData)
            .eq('id', id)
            .eq('company_id', companyId)
            .select()
            .single();
        if (error) {
            logError(error, { context: `updateLocationInDB: ${id}` });
            if (error.code === '23505') throw new Error('A location with this name already exists.');
            throw error;
        }
        return LocationSchema.parse(data);
    });
}

export async function deleteLocationFromDB(id: string, companyId: string): Promise<void> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteLocationFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase.rpc('delete_location_and_unassign_inventory', {
            p_location_id: id,
            p_company_id: companyId,
        });

        if (error) {
            logError(error, { context: `deleteLocationFromDB: ${id}` });
            throw error;
        }
    });
}

// Supplier DB Functions
export async function getSupplierByIdFromDB(id: string, companyId: string): Promise<Supplier | null> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getSupplierByIdFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('vendors')
            .select('*')
            .eq('id', id)
            .eq('company_id', companyId)
            .maybeSingle();
        if (error) {
            logError(error, { context: `getSupplierByIdFromDB: ${id}` });
            throw error;
        }
        return data ? SupplierSchema.parse(data) : null;
    });
}

export async function createSupplierInDb(companyId: string, supplierData: SupplierFormData): Promise<Supplier> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('createSupplierInDb', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('vendors')
            .insert({ ...supplierData, company_id: companyId })
            .select()
            .single();
        if (error) {
            logError(error, { context: 'createSupplierInDb' });
            if (error.code === '23505') throw new Error('A supplier with this name already exists.');
            throw error;
        }
        return SupplierSchema.parse(data);
    });
}

export async function updateSupplierInDb(id: string, companyId: string, supplierData: SupplierFormData): Promise<Supplier> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('updateSupplierInDb', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('vendors')
            .update(supplierData)
            .eq('id', id)
            .eq('company_id', companyId)
            .select()
            .single();
        if (error) {
            logError(error, { context: `updateSupplierInDb: ${id}` });
            if (error.code === '23505') throw new Error('A supplier with this name already exists.');
            throw error;
        }
        return SupplierSchema.parse(data);
    });
}

export async function deleteSupplierFromDb(id: string, companyId: string): Promise<void> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteSupplierFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        const { error } = await supabase.rpc('delete_supplier_and_catalogs', {
            p_supplier_id: id,
            p_company_id: companyId,
        });

        if (error) {
            logError(error, { context: `deleteSupplierFromDb: ${id}` });
            // Make the error message more user-friendly
            if (error.message.includes('Cannot delete supplier with active purchase orders')) {
                throw new Error('Cannot delete supplier. They are associated with active purchase orders. Please reassign or delete the POs first.');
            }
            throw error;
        }
    });
}

export async function deleteInventoryItemsFromDb(companyId: string, skus: string[]): Promise<void> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('deleteInventoryItemsFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        // Data integrity check: ensure these SKUs are not in use.
        const { count: orderItemsCount, error: orderItemsError } = await supabase
            .from('order_items')
            .select('id', { count: 'exact', head: true })
            .in('sku', skus)
            .limit(1);

        if (orderItemsError) throw orderItemsError;
        if (orderItemsCount && orderItemsCount > 0) {
            throw new Error('One or more items could not be deleted because they are part of historical sales orders.');
        }

        const { count: poItemsCount, error: poItemsError } = await supabase
            .from('purchase_order_items')
            .select('id', { count: 'exact', head: true })
            .in('sku', skus)
            .limit(1);

        if (poItemsError) throw poItemsError;
        if (poItemsCount && poItemsCount > 0) {
            throw new Error('One or more items could not be deleted because they are part of historical purchase orders.');
        }

        const { error } = await supabase
            .from('inventory')
            .delete()
            .eq('company_id', companyId)
            .in('sku', skus);
            
        if (error) {
            logError(error, { context: `deleteInventoryItemsFromDb for company ${companyId}` });
            throw error;
        }
    });
}

export async function updateInventoryItemInDb(companyId: string, sku: string, itemData: InventoryUpdateData): Promise<UnifiedInventoryItem> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('updateInventoryItemInDb', async () => {
        const supabase = getServiceRoleClient();

        const { data, error } = await supabase
            .from('inventory')
            .update({
                name: itemData.name,
                category: itemData.category,
                cost: itemData.cost,
                reorder_point: itemData.reorder_point,
                landed_cost: itemData.landed_cost,
                barcode: itemData.barcode,
                location_id: itemData.location_id,
            })
            .eq('company_id', companyId)
            .eq('sku', sku)
            .select(`
                *,
                location:locations ( name )
            `)
            .single();

        if (error) {
            logError(error, { context: `updateInventoryItemInDb: ${sku}` });
            throw error;
        }

        // We need to fetch the stats for the unified view separately now.
        const { data: stats } = await supabase.rpc('execute_dynamic_query', {
            query_text: `
                WITH monthly_sales AS (
                    SELECT 
                        oi.sku,
                        SUM(oi.quantity) as units_sold
                    FROM order_items oi
                    JOIN orders o ON oi.sale_id = o.id
                    WHERE o.company_id = '${companyId}' AND o.sale_date >= CURRENT_DATE - INTERVAL '30 days' AND oi.sku = '${sku}'
                    GROUP BY oi.sku
                )
                SELECT 
                    COALESCE(ms.units_sold, 0) as monthly_units_sold,
                    ((${data.price || 0} - COALESCE(${data.landed_cost || data.cost}, 0)) * COALESCE(ms.units_sold, 0)) as monthly_profit
                FROM monthly_sales ms
            `
        }).single();


        // Transform the result to match UnifiedInventoryItem structure
        const transformedData: UnifiedInventoryItem = {
            ...data,
            product_name: data.name,
            total_value: data.quantity * data.cost,
            location_name: data.location?.name || null,
            monthly_units_sold: (stats as any)?.monthly_units_sold || 0,
            monthly_profit: (stats as any)?.monthly_profit || 0,
        };
        delete (transformedData as any).location;
        
        return transformedData;
    });
}

// Integration Functions
export async function getIntegrationsByCompanyId(companyId: string): Promise<Integration[]> {
  if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
  return withPerformanceTracking('getIntegrationsByCompanyId', async () => {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
      .from('integrations')
      .select('*')
      .eq('company_id', companyId);
    if (error) {
      logError(error, { context: `getIntegrationsByCompanyId for company ${companyId}` });
      throw error;
    }
    return data || [];
  });
}

export async function deleteIntegrationFromDb(integrationId: string, companyId: string): Promise<void> {
    if (!isValidUuid(integrationId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteIntegrationFromDb', async () => {
        const supabase = getServiceRoleClient();
        const { error } = await supabase
            .from('integrations')
            .delete()
            .eq('id', integrationId)
            .eq('company_id', companyId);
        
        if(error) {
            logError(error, { context: `Failed to delete integration ${integrationId}`});
            throw error;
        }
    });
}

export async function getSupplierPerformanceFromDB(companyId: string): Promise<SupplierPerformanceReport[]> {
  if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');

  return withPerformanceTracking('getSupplierPerformanceFromDB', async () => {
    const supabase = getServiceRoleClient();
    
    // This query calculates supplier performance metrics from historical purchase orders.
    const query = `
      SELECT
          v.vendor_name as supplier_name,
          COUNT(po.id) as total_completed_orders,
          -- Calculate the on-time delivery rate as a percentage
          (AVG(CASE WHEN po.updated_at <= po.expected_date THEN 1 ELSE 0 END) * 100) as on_time_delivery_rate,
          -- Calculate the average variance from the expected date in days
          AVG(DATE_PART('day', po.updated_at - po.expected_date)) as average_delivery_variance_days,
          -- Calculate the average lead time from order date to received date
          AVG(DATE_PART('day', po.updated_at - po.order_date)) as average_lead_time_days
      FROM purchase_orders po
      JOIN vendors v ON po.supplier_id = v.id
      WHERE po.company_id = '${companyId}'
        AND po.status = 'received' -- Only consider completed orders for performance metrics
        AND po.expected_date IS NOT NULL
        AND po.updated_at IS NOT NULL
      GROUP BY v.vendor_name
      ORDER BY on_time_delivery_rate DESC;
    `;
        
    const { data, error } = await supabase.rpc('execute_dynamic_query', {
        query_text: query.trim().replace(/;/g, '')
    });
    
    if (error) {
        logError(error, { context: `Error getting supplier performance for company ${companyId}` });
        throw new Error(`Could not generate supplier performance report: ${error.message}`);
    }

    // Since the query returns numbers as strings from json_agg, we need to parse them.
    const parsedData = z.array(z.object({
        supplier_name: z.string(),
        total_completed_orders: z.coerce.number(),
        on_time_delivery_rate: z.coerce.number(),
        average_delivery_variance_days: z.coerce.number(),
        average_lead_time_days: z.coerce.number(),
    })).safeParse(data || []);

    if (!parsedData.success) {
        logError(parsedData.error, { context: 'Zod parsing error for supplier performance report' });
        return [];
    }
    return parsedData.data;
  });
}

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; category?: string, location?: string, supplier?: string }): Promise<UnifiedInventoryItem[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getUnifiedInventoryFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_unified_inventory', {
            p_company_id: companyId,
            p_query: params.query || null,
            p_category: params.category || null,
            p_location_id: params.location ? (isValidUuid(params.location) ? params.location : null) : null,
            p_supplier_id: params.supplier ? (isValidUuid(params.supplier) ? params.supplier : null) : null,
        });

        if (error) {
            logError(error, { context: 'getUnifiedInventoryFromDB RPC failed' });
            throw new Error(`Could not load inventory data: ${error.message}`);
        }
        return (data || []) as UnifiedInventoryItem[];
    });
}


export async function getInventoryLedgerForSkuFromDB(companyId: string, sku: string): Promise<InventoryLedgerEntry[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getInventoryLedgerForSku', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_inventory_ledger_for_sku', {
            p_company_id: companyId,
            p_sku: sku,
        });

        if (error) {
            logError(error, { context: `Error fetching ledger for SKU ${sku}` });
            throw error;
        }

        return z.array(InventoryLedgerEntrySchema).parse(data || []);
    });
}