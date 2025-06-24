
'use server';

/**
 * @fileoverview
 * This file contains server-side functions for querying the Supabase database.
 * It uses the Supabase service role key for direct data access. All functions
 * are scoped by companyId to ensure data isolation between tenants.
 * All functions will throw an error if the database query fails.
 */

import { createClient } from '@supabase/supabase-js';
import type { DashboardMetrics, InventoryItem, Supplier, Alert } from '@/types';
import { subDays, differenceInDays, parseISO, isAfter, isBefore } from 'date-fns';

function getSupabase() {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceKey) {
        console.error("Supabase service role credentials are not configured on the server.");
        throw new Error("Database service is not available. Please check server configuration.");
    }
  
    return createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false
      }
    });
}

export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
  const supabase = getSupabase();
  
  const { data: inventory, error: inventoryError } = await supabase
    .from('inventory')
    .select('quantity, cost, last_sold_date, reorder_point, name')
    .eq('company_id', companyId);

  if (inventoryError) {
    console.error('Error fetching inventory for dashboard:', inventoryError);
    throw new Error('Failed to fetch dashboard metrics.');
  }
  if (!inventory) return { inventoryValue: 0, deadStockValue: 0, onTimeDeliveryRate: 0, predictiveAlert: null };

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

  if (poError) {
    console.error('Error fetching purchase orders for dashboard:', poError);
    throw new Error('Failed to fetch dashboard metrics.');
  }

  let onTimeDeliveryRate = 0;
  if (purchaseOrders && purchaseOrders.length > 0) {
      let onTimeDeliveries = 0;
      purchaseOrders.forEach(po => {
          if (po.delivery_date && po.expected_date && !isAfter(parseISO(po.delivery_date), parseISO(po.expected_date))) {
              onTimeDeliveries++;
          }
      });
      onTimeDeliveryRate = (onTimeDeliveries / purchaseOrders.length) * 100;
  }

  const lowStockItem = inventory.find(item => item.quantity <= item.reorder_point);
  const predictiveAlert = lowStockItem ? {
      item: lowStockItem.name,
      days: 7 // Placeholder, as sales velocity data is not available
  } : null;

  return {
      inventoryValue: Math.round(inventoryValue),
      deadStockValue: Math.round(deadStockValue),
      onTimeDeliveryRate: Math.round(onTimeDeliveryRate),
      predictiveAlert
  };
}

export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
  const supabase = getSupabase();
  const { data, error } = await supabase
    .from('inventory')
    .select('*')
    .eq('company_id', companyId)
    .order('name');
    
  if (error) {
    console.error('Error fetching inventory:', error);
    throw new Error('Could not load inventory data.');
  }
  return data || [];
}

export async function getDeadStockFromDB(companyId: string): Promise<InventoryItem[]> {
    const supabase = getSupabase();
    const ninetyDaysAgo = subDays(new Date(), 90).toISOString();
    const { data, error } = await supabase
        .from('inventory')
        .select('*')
        .eq('company_id', companyId)
        .lt('last_sold_date', ninetyDaysAgo);

    if (error) {
        console.error('Error fetching dead stock:', error);
        throw new Error('Could not load dead stock data.');
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

export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    const supabase = getSupabase();
    
    const { data: vendors, error: vendorError } = await supabase
        .from('vendors')
        .select('*')
        .eq('company_id', companyId);
    
    if (vendorError) {
        console.error('Error fetching vendors:', vendorError);
        throw new Error('Could not load suppliers data.');
    }
    if (!vendors) return [];

    const { data: purchaseOrders, error: poError } = await supabase
        .from('purchase_orders')
        .select('vendor_name, cost, item, expected_date, delivery_date, quantity')
        .eq('company_id', companyId);
    
    if (poError) {
        console.error('Error fetching purchase orders for suppliers:', poError);
        throw new Error('Could not load suppliers data.');
    }

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
}

export async function getVendorsFromDB(companyId: string) {
    const supabase = getSupabase();
    const { data, error } = await supabase
        .from('vendors')
        .select('*')
        .eq('company_id', companyId);

    if (error) {
        console.error('Error fetching vendors from DB', error);
        throw new Error('Could not load vendor data.');
    }
    return data || [];
}

export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
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
}

export async function getInventoryFromDB(companyId: string) {
    return getInventoryItems(companyId);
}

export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    const supabase = getSupabase();
    const lowerCaseQuery = query.toLowerCase();

    const { data, error } = await supabase.rpc('get_chart_data', {
        p_company_id: companyId,
        p_query: lowerCaseQuery
    });
    
    if (error) {
        console.error(`Error in getDataForChart for query "${query}":`, error);
        // We don't throw here so the chat doesn't break, just returns no chart.
        return [];
    }

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
