
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
  company_id: string;
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
  isError?: boolean;
};

// Represents the configuration for a dynamically generated chart.
export type ChartConfig = {
    chartType: 'bar' | 'pie' | 'line' | 'treemap' | 'scatter';
    title?: string;
    data: any[];
    config: {
        dataKey: string;
        nameKey: string;
        xAxisKey?: string;
        yAxisKey?: string;
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

export type DeadStockItem = {
    sku: string;
    product_name: string;
    quantity: number;
    cost: number;
    total_value: number;
    last_sale_date: string | null;
};

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
    totalSalesValue: number;
    totalProfit: number;
    returnRate: number;
    totalInventoryValue: number;
    lowStockItemsCount: number;
    totalOrders: number;
    totalCustomers: number;
    averageOrderValue: number;
    salesTrendData: { date: string; Sales: number }[];
    inventoryByCategoryData: { name: string; value: number }[];
    topCustomersData: { name: string; value: number }[];
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

export type UnifiedInventoryItem = {
  sku: string;
  product_name: string;
  category: string | null;
  quantity: number;
  cost: number;
  total_value: number;
};
