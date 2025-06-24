
'use server';

/**
 * @fileoverview
 * This file provides functions to query your Supabase database.
 * It connects to the actual database tables to fetch real-time data.
 */

import { createClient } from '@supabase/supabase-js';
import type { DashboardMetrics, InventoryItem, Supplier, Alert } from '@/types';
import { subDays, differenceInDays, parseISO, isAfter, isBefore } from 'date-fns';

function getSupabase() {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceKey) {
        throw new Error("Supabase credentials are not configured.");
    }
  
    return createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false
      }
    });
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const supabase = getSupabase();
  const defaultValue: DashboardMetrics = {
    inventoryValue: 0,
    deadStockValue: 0,
    onTimeDeliveryRate: 0,
    predictiveAlert: null
  };

  try {
    const { data: inventory, error: inventoryError } = await supabase
      .from('inventory')
      .select('quantity, cost, last_sold_date, reorder_point, name')
      .eq('company_id', companyId);

    if (inventoryError) throw inventoryError;
    if (!inventory) return defaultValue;

    const ninetyDaysAgo = subDays(new Date(), 90);
    const inventoryValue = inventory.reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);
    const deadStockValue = inventory
        .filter(item => item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo))
        .reduce((sum, item) => sum + (item.quantity * Number(item.cost)), 0);

    const { data: purchaseOrders, error: poError } = await supabase
        .from('purchase_orders')
        .select('expected_date, delivery_date')
        .eq('company_id', companyId)
        .not('delivery_date', 'is', null);

    if (poError) throw poError;

    let onTimeDeliveries = 0;
    if (purchaseOrders && purchaseOrders.length > 0) {
        purchaseOrders.forEach(po => {
            if (po.delivery_date && po.expected_date && !isAfter(parseISO(po.delivery_date), parseISO(po.expected_date))) {
                onTimeDeliveries++;
            }
        });
        const onTimeDeliveryRate = (onTimeDeliveries / purchaseOrders.length) * 100;
        defaultValue.onTimeDeliveryRate = Math.round(onTimeDeliveryRate);
    }

    const lowStockItem = inventory.find(item => item.quantity <= item.reorder_point);
    const predictiveAlert = lowStockItem ? {
        item: lowStockItem.name,
        days: 7 // Placeholder, as sales velocity data is not available
    } : null;

    return {
        inventoryValue: Math.round(inventoryValue),
        deadStockValue: Math.round(deadStockValue),
        onTimeDeliveryRate: defaultValue.onTimeDeliveryRate,
        predictiveAlert
    };

  } catch (error) {
    console.error('Error in getDashboardMetrics:', error);
    return defaultValue;
  }
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
  const supabase = getSupabase();
  try {
    const { data, error } = await supabase
      .from('inventory')
      .select('*')
      .eq('company_id', companyId)
      .order('name');
      
    if (error) {
      console.error('Error fetching inventory:', error);
      return [];
    }
    return data || [];
  } catch (error) {
      console.error('Error in getInventoryItems:', error);
      return [];
  }
}

export async function getDeadStockFromDB(companyId: string): Promise<InventoryItem[]> {
    const supabase = getSupabase();
    try {
        const ninetyDaysAgo = subDays(new Date(), 90).toISOString();
        const { data, error } = await supabase
            .from('inventory')
            .select('*')
            .eq('company_id', companyId)
            .lt('last_sold_date', ninetyDaysAgo);

        if (error) {
            console.error('Error fetching dead stock:', error);
            return [];
        }
        return data || [];
    } catch (error) {
        console.error('Error in getDeadStockFromDB:', error);
        return [];
    }
}

export async function getDeadStockPageData(companyId: string) {
    const defaultValue = { deadStock: [], totalValue: 0, totalUnits: 0, averageAge: 0 };
    try {
        const deadStock = await getDeadStockFromDB(companyId);
        if (deadStock.length === 0) return defaultValue;

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
    } catch (error) {
        console.error('Error in getDeadStockPageData:', error);
        return defaultValue;
    }
}

export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    const supabase = getSupabase();
    try {
        const { data: vendors, error: vendorError } = await supabase
            .from('vendors')
            .select('*')
            .eq('company_id', companyId);
        
        if (vendorError) throw vendorError;
        if (!vendors) return [];

        const { data: purchaseOrders, error: poError } = await supabase
            .from('purchase_orders')
            .select('vendor_name, cost, item, expected_date, delivery_date, quantity')
            .eq('company_id', companyId);
        
        if (poError) throw poError;

        return vendors.map(vendor => {
            const vendorPOs = purchaseOrders?.filter(po => po.vendor_name === vendor.vendor_name) || [];
            
            const totalSpend = vendorPOs.reduce((sum, po) => sum + (Number(po.cost) * po.quantity), 0);
            const itemsSupplied = [...new Set(vendorPOs.map(po => po.item))];
            
            const onTimePOs = vendorPOs.filter(po => po.delivery_date && po.expected_date && !isAfter(parseISO(po.delivery_date), parseISO(po.expected_date)));
            const onTimeDeliveryRate = vendorPOs.length > 0 ? (onTimePOs.length / vendorPOs.length) * 100 : 95; // Default 95 if no data

            return {
                id: vendor.id,
                name: vendor.vendor_name,
                contact_info: vendor.contact_info,
                address: vendor.address,
                terms: vendor.terms,
                onTimeDeliveryRate: Math.round(onTimeDeliveryRate),
                totalSpend,
                itemsSupplied
            };
        });

    } catch (error) {
        console.error('Error in getSuppliersFromDB:', error);
        return [];
    }
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    const supabase = getSupabase();
    try {
        const inventory = await getInventoryItems(companyId);
        if (!inventory) return [];

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
    } catch (error) {
        console.error('Error in getAlertsFromDB:', error);
        return [];
    }
}

export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    const supabase = getSupabase();
    const lowerCaseQuery = query.toLowerCase();

    try {
        if (lowerCaseQuery.includes('inventory value by category')) {
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

        if (lowerCaseQuery.includes('warehouse distribution')) {
            const { data, error } = await supabase
                .from('inventory')
                .select('quantity, warehouse_name')
                .eq('company_id', companyId);
            if (error) throw error;
            const aggregated = data.reduce((acc, item) => {
                const locationName = item.warehouse_name || 'Unknown Location';
                acc[locationName] = (acc[locationName] || 0) + item.quantity;
                return acc;
            }, {} as Record<string, number>);
            return Object.entries(aggregated).map(([name, value]) => ({ name, value }));
        }

        if (lowerCaseQuery.includes('slowest moving') || lowerCaseQuery.includes('dead stock')) {
            const { data, error } = await supabase
                .from('inventory')
                .select('name, last_sold_date')
                .eq('company_id', companyId)
                .not('last_sold_date', 'is', null)
                .order('last_sold_date', { ascending: true })
                .limit(5);
            if (error) throw error;
            return data.map(item => ({
                name: item.name,
                value: differenceInDays(new Date(), parseISO(item.last_sold_date!))
            }));
        }
        
        if (lowerCaseQuery.includes('supplier performance')) {
             const suppliers = await getSuppliersFromDB(companyId);
             return suppliers.map(s => ({
                 name: s.name,
                 value: s.onTimeDeliveryRate
             }));
        }

        return [];
    } catch (error) {
        console.error(`Error in getDataForChart for query "${query}":`, error);
        return [];
    }
}
