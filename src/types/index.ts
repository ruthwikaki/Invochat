

import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';

// Extend the Supabase User type to include our custom app_metadata
// which may or may not be present on a new user object.
export type User = Omit<SupabaseUser, 'app_metadata'> & {
  app_metadata?: {
    company_id?: string;
    // other metadata properties can be added here
  };
};

export type Conversation = {
  id: string; // UUID
  user_id: string; // UUID
  company_id: string; // UUID
  title: string;
  created_at: string; // ISO String
  last_accessed_at: string; // ISO String
  is_starred: boolean;
};

export type Message = {
  id: string;
  conversation_id: string;
  role: 'user' | 'assistant';
  content: string;
  visualization?: {
    type: 'table' | 'chart' | 'alert';
    data: any;
    config?: {
        title?: string;
        [key: string]: any;
    };
  } | null;
  confidence?: number | null;
  assumptions?: string[] | null;
  created_at: string;
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

export type DashboardMetrics = {
    inventoryValue: number;
    deadStockValue: number;
    lowStockCount: number;
    totalSKUs: number;
    totalSuppliers: number;
    totalSalesValue: number;
    salesTrendData: { date: string; Sales: number }[];
    inventoryByCategoryData: { name: string; value: number }[];
};

export type CompanySettings = {
  company_id: string;
  dead_stock_days: number;
  overstock_multiplier: number;
  high_value_threshold: number;
  fast_moving_days: number;
  custom_rules: Record<string, any> | null;
  created_at?: string;
  updated_at?: string;
};
