
import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';

export type User = Omit<SupabaseUser, 'app_metadata' | 'role'> & {
  app_metadata?: {
    company_id?: string;
  };
  role?: 'Owner' | 'Admin' | 'Member';
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

export const SupplierSchema = z.object({
    id: z.string().uuid(),
    name: z.string().min(1),
    contact_info: z.string().email(),
    address: z.string().nullable(),
    terms: z.string().nullable(),
    account_number: z.string().nullable(),
}).transform(data => ({
    id: data.id,
    name: (data as any).vendor_name || data.name, // Handle raw data from DB
    contact_info: data.contact_info,
    address: data.address,
    terms: data.terms,
    account_number: data.account_number,
}));
export type Supplier = z.infer<typeof SupplierSchema>;


export const DeadStockItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity: z.number(),
    cost: z.number(),
    total_value: z.number(),
    last_sale_date: z.string().nullable(),
});
export type DeadStockItem = z.infer<typeof DeadStockItemSchema>;


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

export const CompanySettingsSchema = z.object({
  company_id: z.string().uuid(),
  dead_stock_days: z.number(),
  overstock_multiplier: z.number(),
  high_value_threshold: z.number(),
  fast_moving_days: z.number(),
  currency: z.string().nullable().default('USD'),
  timezone: z.string().nullable().default('UTC'),
  tax_rate: z.number().nullable().default(0),
  theme_primary_color: z.string().nullable().default('262 84% 59%'),
  theme_background_color: z.string().nullable().default('0 0% 96%'),
  theme_accent_color: z.string().nullable().default('0 0% 90%'),
  custom_rules: z.any().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }),
});
export type CompanySettings = z.infer<typeof CompanySettingsSchema>;


export type UnifiedInventoryItem = {
  sku: string;
  product_name: string;
  category: string | null;
  quantity: number;
  cost: number;
  total_value: number;
};

export type TeamMember = {
  id: string;
  email: string | undefined;
  role: 'Owner' | 'Admin' | 'Member';
};
