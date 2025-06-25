
import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';

// Extend the Supabase User type to include our custom app_metadata
// which is automatically added by our database trigger.
export type User = Omit<SupabaseUser, 'app_metadata'> & {
  app_metadata: {
    company_id: string;
    // other metadata properties can be added here
  };
};

export type Message = {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: ReactNode;
  timestamp: number;
};

// Represents the configuration for a dynamically generated chart.
export type ChartConfig = {
    chartType: 'bar' | 'pie' | 'line';
    title: string;
    data: any[];
    config: {
        dataKey: string;
        nameKey?: string;
        fill?: string;
        stroke?: string;
        // For line/bar charts
        xAxisKey?: string;
        // For pie charts
        innerRadius?: number;
        outerRadius?: number;
        paddingAngle?: number;
    }
}

export type AssistantMessagePayload = {
  id: string;
  role: 'assistant';
  content?: string;
  component?: 'DeadStockTable' | 'SupplierPerformanceTable' | 'ReorderList' | 'DynamicChart';
  props?: any;
};

// Data models based on database schema
// This type is based on the `get_suppliers` RPC function, updated to match vendors table.
export type Supplier = {
    id: string; // UUID
    name: string;
    contact_info: string;
    address: string | null;
    terms: string;
    account_number: string | null;
}

export type InventoryItem = {
    id: string; // UUID
    company_id: string; // UUID
    sku: string;
    name: string;
    description: string | null;
    category: string | null;
    quantity: number;
    cost: number;
    price: number;
    reorder_point: number;
    reorder_qty: number;
    supplier_name: string | null;
    warehouse_name: string | null;
    last_sold_date: string | null; // ISO String
}

export type Alert = {
    id: string;
    type: 'low_stock' | 'dead_stock';
    title: string;
    message: string;
    severity: 'warning' | 'info';
    timestamp: string;
    metadata: {
        productId?: string;
        productName?: string;
        currentStock?: number;
        reorderPoint?: number;
        lastSoldDate?: string | null;
        value?: number;
    };
};

// Corrected DashboardMetrics to remove the metric that can't be calculated.
export type DashboardMetrics = {
    inventoryValue: number;
    deadStockValue: number;
    predictiveAlert: {
        item: string;
        days: number;
    } | null;
};
