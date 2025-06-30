
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
    data: Record<string, unknown>[];
    config?: {
        title?: string;
        [key: string]: unknown;
    };
  } | null;
  confidence?: number | null;
  assumptions?: string[] | null;
  created_at: string;
  isError?: boolean;
};

export const SupplierSchema = z.object({
    id: z.string().uuid(),
    vendor_name: z.string().min(1),
    contact_info: z.string().nullable(),
    address: z.string().nullable(),
    terms: z.string().nullable(),
    account_number: z.string().nullable(),
}).transform(data => ({
    id: data.id,
    name: data.vendor_name,
    contact_info: data.contact_info || 'N/A',
    address: data.address,
    terms: data.terms,
    account_number: data.account_number,
}));
export type Supplier = z.infer<typeof SupplierSchema>;


export const DeadStockItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity: z.coerce.number(),
    cost: z.coerce.number(),
    total_value: z.coerce.number(),
    last_sale_date: z.string().nullable().optional(),
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
  dead_stock_days: z.number().default(90),
  overstock_multiplier: z.number().default(3),
  high_value_threshold: z.number().default(1000),
  fast_moving_days: z.number().default(30),
  currency: z.string().nullable().optional().default('USD'),
  timezone: z.string().nullable().optional().default('UTC'),
  tax_rate: z.number().nullable().optional().default(0),
  theme_primary_color: z.string().nullable().optional().default('262 84% 59%'),
  theme_background_color: z.string().nullable().optional().default('0 0% 96%'),
  theme_accent_color: z.string().nullable().optional().default('0 0% 90%'),
  custom_rules: z.record(z.unknown()).nullable().optional(),
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
  reorder_point: number | null;
};

export type TeamMember = {
  id: string;
  email: string | undefined;
  role: 'Owner' | 'Admin' | 'Member';
};

export const AnomalySchema = z.object({
    date: z.string(),
    daily_revenue: z.coerce.number(),
    daily_customers: z.coerce.number(),
    avg_revenue: z.coerce.number(),
    avg_customers: z.coerce.number(),
    anomaly_type: z.string(),
});
export type Anomaly = z.infer<typeof AnomalySchema>;
