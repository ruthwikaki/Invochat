

'use server';

/**
 * @fileoverview
 * This file is the single source of truth for all direct database queries.
 * It uses the Supabase Admin client (service_role) to bypass Row Level Security (RLS).
 * SECURITY: All functions in this file MUST manually filter queries by `companyId`.
 */

import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { DashboardMetrics, Alert, CompanySettings, UnifiedInventoryItem, User, TeamMember, Anomaly, PurchaseOrder, PurchaseOrderCreateInput, PurchaseOrderUpdateInput, ReorderSuggestion, ReceiveItemsFormInput, ChannelFee, Location, LocationFormData, SupplierFormData, Supplier, InventoryUpdateData, SupplierPerformanceReport, InventoryLedgerEntry, ExportJob, Customer } from '@/types';
import { CompanySettingsSchema, DeadStockItemSchema, SupplierSchema, AnomalySchema, PurchaseOrderSchema, ReorderSuggestionSchema, ChannelFeeSchema, LocationSchema, LocationFormSchema, SupplierFormSchema, InventoryUpdateSchema, InventoryLedgerEntrySchema, ExportJobSchema, CustomerSchema } from '@/types';
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
export const isValidUuid = (uuid: string) => /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);

export async function withPerformanceTracking<T>(
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
        const { error } = await supabase.rpc('refresh_dashboard_metrics_for_company', {
            p_company_id: companyId,
        });
        if (error) {
            logError(error, { context: `Failed to refresh dashboard metrics for company ${companyId}` });
            // Don't throw, as this is a background optimization, not a critical failure
        } else {
            logger.info(`[DB Service] Refreshed dashboard metrics for company ${companyId}`);
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

export async function getDashboardMetrics(companyId: string, dateRange: string = '30d'): Promise<DashboardMetrics> {
  if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
  const cacheKey = `company:${companyId}:dashboard:${dateRange}`;

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
        logError(error, { context: `Redis error getting cache for ${cacheKey}` });
    }
  }

  const fetchAndCacheMetrics = async (): Promise<DashboardMetrics> => {
    return withPerformanceTracking('getDashboardMetricsOptimized', async () => {
        const supabase = getServiceRoleClient();
        
        const { data: mvData, error: mvError } = await supabase
            .from('company_dashboard_metrics')
            .select('inventory_value, low_stock_count, total_skus')
            .eq('company_id', companyId)
            .maybeSingle();

        if (mvError) {
            logError(mvError, { context: `Could not fetch from dashboard metrics table for company ${companyId}` });
        }
        
        const { data: rpcData, error: rpcError } = await supabase.rpc('get_dashboard_metrics', {
            p_company_id: companyId
        });
        
        if (rpcError) {
            logError(rpcError, { context: `Dashboard RPC failed for company ${companyId}` });
            throw rpcError;
        }

        const metrics = rpcData || {};
        
        const { count: customerCount, error: customerError } = await supabase.from('customers').select('id', { count: 'exact', head: true }).eq('company_id', companyId);

        if (customerError) {
            logError(customerError, { context: `Could not fetch customer count for company ${companyId}`});
        }

        const finalMetrics: DashboardMetrics = {
            totalSalesValue: Math.round(metrics.totalSalesValue || 0),
            totalProfit: Math.round(metrics.totalProfit || 0),
            totalInventoryValue: Math.round(mvData?.inventory_value || 0),
            lowStockItemsCount: mvData?.low_stock_count || 0,
            deadStockItemsCount: metrics.deadStockItemsCount || 0,
            totalSkus: mvData?.total_skus || 0,
            totalOrders: metrics.totalOrders || 0,
            totalCustomers: customerCount || 0,
            averageOrderValue: metrics.averageOrderValue || 0,
            salesTrendData: (metrics.salesTrendData as { date: string; Sales: number }[] | null) || [],
            inventoryByCategoryData: (metrics.inventoryByCategoryData as { name: string; value: number }[] | null) || [],
            topCustomersData: (metrics.topCustomersData as { name: string; value: number }[] | null) || [],
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

  return fetchAndCacheMetrics();
}

async function getRawDeadStockData(companyId: string, settings: CompanySettings) {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    const supabase = getServiceRoleClient();
    const deadStockDays = settings.dead_stock_days;

    const { data, error } = await supabase.rpc('get_dead_stock_alerts_data', {
        p_company_id: companyId,
        p_dead_stock_days: deadStockDays
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

export async function getPurchaseOrdersFromDB(companyId: string, params: { query?: string; limit: number; offset: number }): Promise<{ items: PurchaseOrder[], totalCount: number }> {
     if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
     return withPerformanceTracking('getPurchaseOrdersFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase.rpc('get_purchase_orders', {
            p_company_id: companyId,
            p_query: params.query || null,
            p_limit: params.limit,
            p_offset: params.offset,
        });

        if (error) {
            logError(error, { context: 'Error fetching purchase orders from DB' });
            throw new Error(`Could not load purchase order data: ${error.message}`);
        }
        
        const result = data as { items: any[], totalCount: number };

        return {
            items: z.array(PurchaseOrderSchema.partial()).parse(result.items || []),
            totalCount: result.totalCount || 0,
        };
     });
}

export async function getPurchaseOrderByIdFromDB(poId: string, companyId: string): Promise<PurchaseOrder | null> {
    if (!isValidUuid(poId) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('getPurchaseOrderByIdFromDB', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase.rpc('get_purchase_order_details', {
            p_po_id: poId,
            p_company_id: companyId,
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
        const settings = await getSettings(companyId);
        
        const { data, error } = await supabase.rpc('get_alerts', { 
            p_company_id: companyId,
            p_dead_stock_days: settings.dead_stock_days,
            p_fast_moving_days: settings.fast_moving_days,
            p_predictive_stock_days: config.businessLogic.predictiveStockDays,
        });

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

export async function getAnomalyInsightsFromDB(companyId: string): Promise<Anomaly[]> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('generateAnomalyInsights', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase.rpc('get_anomaly_insights', {
            p_company_id: companyId
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
        
        const { data, error } = await supabase.rpc('get_distinct_categories', {
            p_company_id: companyId
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
            .eq('company_id', companyId)
            .is('deleted_at', null); // Only fetch active members

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
                role: 'Member' // Default role for invites
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
    companyId: string,
    performingUserId: string,
): Promise<{ success: boolean; error?: string }> {
    if (!isValidUuid(userIdToRemove) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('removeTeamMemberFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        // Soft-delete the user's association with the company
        const { error } = await supabase
            .from('users')
            .update({ deleted_at: new Date().toISOString() })
            .eq('id', userIdToRemove)
            .eq('company_id', companyId);

        if (error) {
            logError(error, { context: `Failed to soft-delete user ${userIdToRemove} from company ${companyId}` });
            return { success: false, error: error.message };
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
            logError(authUpdateError, { context: `Failed to auth role for ${memberIdToUpdate}` });
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

        const { data, error } = await supabase.rpc('get_reorder_suggestions', {
            p_company_id: companyId,
            p_fast_moving_days: settings.fast_moving_days
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

export async function softDeleteInventoryItemsFromDb(companyId: string, skus: string[], userId: string): Promise<void> {
    if (!isValidUuid(companyId) || !isValidUuid(userId)) throw new Error('Invalid ID format.');

    return withPerformanceTracking('softDeleteInventoryItemsFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        // Data integrity check: ensure these SKUs are not in use.
        const { data: activeReferences, error: refError } = await supabase.rpc('check_inventory_references', {
            p_company_id: companyId,
            p_skus: skus
        });
        
        if (refError) {
            logError(refError, { context: `Error checking inventory references for company ${companyId}` });
            throw refError;
        }

        if (activeReferences && activeReferences.length > 0) {
            const activeSkus = activeReferences.map((ref: {sku: string}) => ref.sku).join(', ');
            throw new Error(`Cannot delete items with active references in orders or POs: ${activeSkus}`);
        }

        const { error } = await supabase
            .from('inventory')
            .update({
                deleted_at: new Date().toISOString(),
                deleted_by: userId
            })
            .eq('company_id', companyId)
            .in('sku', skus)
            .is('deleted_at', null);
            
        if (error) {
            logError(error, { context: `softDeleteInventoryItemsFromDb for company ${companyId}` });
            throw error;
        }
        logger.info(`[DB Service] Soft-deleted ${skus.length} inventory items for company ${companyId}`);
    });
}

export async function updateInventoryItemInDb(companyId: string, sku: string, itemData: InventoryUpdateData): Promise<UnifiedInventoryItem> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('updateInventoryItemInDb', async () => {
        const supabase = getServiceRoleClient();
        
        const { data, error } = await supabase.rpc('update_inventory_item_with_lock', {
            p_company_id: companyId,
            p_sku: sku,
            p_expected_version: itemData.version,
            p_name: itemData.name,
            p_category: itemData.category,
            p_cost: itemData.cost,
            p_reorder_point: itemData.reorder_point,
            p_landed_cost: itemData.landed_cost,
            p_barcode: itemData.barcode,
            p_location_id: itemData.location_id
        }).single();

        if (error) {
            logError(error, { context: `Optimistic lock failed or error updating SKU ${sku}` });
            if (error.message.includes('Update failed. The item may have been modified by someone else.')) {
                throw new Error('Update failed. This item was modified by someone else. Please refresh and try again.');
            }
            throw error;
        }

        const { data: fullData } = await getUnifiedInventoryFromDB(companyId, { sku: data.sku, limit: 1 });
        if (!fullData || fullData.items.length === 0) {
            throw new Error('Failed to retrieve updated item details.');
        }

        return fullData.items[0];
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
    
    const { data, error } = await supabase.rpc('get_supplier_performance', {
        p_company_id: companyId
    });
    
    if (error) {
        logError(error, { context: `Error getting supplier performance for company ${companyId}` });
        throw new Error(`Could not generate supplier performance report: ${error.message}`);
    }

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

export async function getUnifiedInventoryFromDB(companyId: string, params: { query?: string; category?: string; location?: string; supplier?: string; limit?: number; offset?: number; sku?: string }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getUnifiedInventoryFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_unified_inventory', {
            p_company_id: companyId,
            p_query: params.query || null,
            p_category: params.category || null,
            p_location_id: params.location ? (isValidUuid(params.location) ? params.location : null) : null,
            p_supplier_id: params.supplier ? (isValidUuid(params.supplier) ? params.supplier : null) : null,
            p_sku_filter: params.sku || null,
            p_limit: params.limit || 50,
            p_offset: params.offset || 0,
        });

        if (error) {
            logError(error, { context: 'getUnifiedInventoryFromDB RPC failed' });
            throw new Error(`Could not load inventory data: ${error.message}`);
        }
        
        const result = data as { items: UnifiedInventoryItem[], totalCount: number };
        
        return {
            items: result.items || [],
            totalCount: result.totalCount || 0,
        };
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

export async function deleteCustomerFromDb(id: string, companyId: string): Promise<void> {
    if (!isValidUuid(id) || !isValidUuid(companyId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('deleteCustomerFromDb', async () => {
        const supabase = getServiceRoleClient();
        
        // Check for existing orders
        const { count, error: countError } = await supabase
            .from('orders')
            .select('id', { count: 'exact', head: true })
            .eq('company_id', companyId)
            .eq('customer_id', id);
            
        if (countError) {
            logError(countError, { context: `Error checking orders for customer ${id}` });
            throw countError;
        }

        if (count && count > 0) {
            // Soft delete
            const { error: updateError } = await supabase
                .from('customers')
                .update({ status: 'deleted', deleted_at: new Date().toISOString() })
                .eq('id', id)
                .eq('company_id', companyId);
            if (updateError) {
                logError(updateError, { context: `Error soft-deleting customer ${id}` });
                throw updateError;
            }
        } else {
            // Hard delete
            const { error: deleteError } = await supabase
                .from('customers')
                .delete()
                .eq('id', id)
                .eq('company_id', companyId);
            if (deleteError) {
                logError(deleteError, { context: `Error hard-deleting customer ${id}` });
                throw deleteError;
            }
        }
    });
}

export async function createExportJobInDb(companyId: string, userId: string): Promise<ExportJob> {
    if (!isValidUuid(companyId) || !isValidUuid(userId)) throw new Error('Invalid ID format.');
    return withPerformanceTracking('createExportJobInDb', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('export_jobs')
            .insert({
                company_id: companyId,
                requested_by_user_id: userId,
                status: 'pending',
            })
            .select()
            .single();
        if (error) {
            logError(error, { context: 'createExportJobInDb' });
            throw error;
        }
        return ExportJobSchema.parse(data);
    });
}

export async function getCustomersFromDB(companyId: string, params: { query?: string; limit: number; offset: number }): Promise<{items: Customer[], totalCount: number}> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getCustomersFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_customers_with_stats', {
            p_company_id: companyId,
            p_query: params.query || null,
            p_limit: params.limit,
            p_offset: params.offset,
        });

        if (error) {
            logError(error, { context: 'getCustomersFromDB RPC failed' });
            throw new Error(`Could not load customer data: ${error.message}`);
        }
        
        const result = data as { items: Customer[], totalCount: number };
        
        return {
            items: z.array(CustomerSchema).parse(result.items || []),
            totalCount: result.totalCount || 0,
        };
    });
}

// Analytics Tools DB Functions
export async function getDemandForecastFromDB(companyId: string): Promise<any> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getDemandForecastFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_demand_forecast', {
            p_company_id: companyId
        });
        if (error) {
            logError(error, { context: `Error fetching demand forecast for company ${companyId}` });
            throw error;
        }
        return data;
    });
}

export async function getAbcAnalysisFromDB(companyId: string): Promise<any> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getAbcAnalysisFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_abc_analysis', {
            p_company_id: companyId
        });
        if (error) {
            logError(error, { context: `Error fetching ABC analysis for company ${companyId}` });
            throw error;
        }
        return data;
    });
}

export async function getGrossMarginAnalysisFromDB(companyId: string): Promise<any> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getGrossMarginAnalysisFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_gross_margin_analysis', {
            p_company_id: companyId
        });
        if (error) {
            logError(error, { context: `Error fetching gross margin analysis for company ${companyId}` });
            throw error;
        }
        return data;
    });
}

export async function getNetMarginByChannelFromDB(companyId: string, channelName: string): Promise<any> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getNetMarginByChannelFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_net_margin_by_channel', {
            p_company_id: companyId,
            p_channel_name: channelName,
        });
        if (error) {
            logError(error, { context: `Error fetching net margin for company ${companyId}, channel ${channelName}` });
            throw error;
        }
        return data;
    });
}

export async function getMarginTrendsFromDB(companyId: string): Promise<any> {
    if (!isValidUuid(companyId)) throw new Error('Invalid Company ID format.');
    return withPerformanceTracking('getMarginTrendsFromDB', async () => {
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase.rpc('get_margin_trends', {
            p_company_id: companyId,
        });
        if (error) {
            logError(error, { context: `Error fetching margin trends for company ${companyId}` });
            throw error;
        }
        return data;
    });
}

export async function logSuccessfulLogin(userId: string, ipAddress: string | null): Promise<void> {
    if (!isValidUuid(userId)) return; // Basic validation
    return withPerformanceTracking('logSuccessfulLogin', async () => {
        const supabase = getServiceRoleClient();
        const { data: user } = await supabase.from('users').select('company_id').eq('id', userId).single();
        
        if (!user) {
            logger.warn(`[Audit] Could not log successful login for non-existent user ID: ${userId}`);
            return;
        }

        const { error } = await supabase.from('audit_log').insert({
            company_id: user.company_id,
            user_id: userId,
            action: 'LOGIN_SUCCESS',
            table_name: 'auth.users',
            record_id: userId,
            ip_address: ipAddress,
            new_data: { event: 'User successfully authenticated.' }
        });
        if (error) {
            logError(error, { context: `Failed to log successful login for user ${userId}` });
        }
    });
}
