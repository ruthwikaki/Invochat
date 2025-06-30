

import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';
import type { Integration } from '@/features/integrations/types';

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
    ...data,
    id: data.id,
    name: data.vendor_name,
    email: data.contact_info, // For convenience in other parts of the app
}));
export type Supplier = z.infer<typeof SupplierSchema>;

export const SupplierFormSchema = z.object({
    vendor_name: z.string().min(2, "Supplier name must be at least 2 characters."),
    contact_info: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    address: z.string().nullable().optional(),
    terms: z.string().nullable().optional(),
    account_number: z.string().nullable().optional(),
});
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;


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
  theme_primary_color: z.string().nullable().optional().default('256 47% 52%'),
  theme_background_color: z.string().nullable().optional().default('0 0% 98%'),
  theme_accent_color: z.string().nullable().optional().default('256 47% 52% / 0.1'),
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
  on_order_quantity: number;
  landed_cost?: number | null;
  barcode?: string | null;
  location_id: string | null;
  location_name: string | null;
};

export const InventoryUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
  cost: z.coerce.number().nonnegative('Cost must be a non-negative number.'),
  reorder_point: z.coerce.number().int().nonnegative('Reorder point must be a non-negative integer.').optional().nullable(),
  landed_cost: z.coerce.number().nonnegative('Landed cost must be a non-negative number.').optional().nullable(),
  barcode: z.string().optional().nullable(),
});
export type InventoryUpdateData = z.infer<typeof InventoryUpdateSchema>;

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

// New types for Purchase Orders
export const PurchaseOrderItemSchema = z.object({
  id: z.string().uuid(),
  po_id: z.string().uuid(),
  sku: z.string(),
  product_name: z.string().optional().nullable(),
  quantity_ordered: z.number().int(),
  quantity_received: z.number().int(),
  unit_cost: z.number(),
  tax_rate: z.number(),
});
export type PurchaseOrderItem = z.infer<typeof PurchaseOrderItemSchema>;

export const PurchaseOrderSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  supplier_id: z.string().uuid().nullable(),
  po_number: z.string(),
  status: z.enum(['draft', 'sent', 'partial', 'received', 'cancelled']),
  order_date: z.string(),
  expected_date: z.string().nullable(),
  total_amount: z.coerce.number(),
  notes: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string().nullable(),
  // For UI display
  supplier_name: z.string().optional().nullable(),
  supplier_email: z.string().email().optional().nullable(),
  items: z.array(PurchaseOrderItemSchema).optional(),
});
export type PurchaseOrder = z.infer<typeof PurchaseOrderSchema>;

const POItemInputSchema = z.object({
    sku: z.string().min(1, 'SKU is required.'),
    product_name: z.string().optional(),
    quantity_ordered: z.coerce.number().positive('Quantity must be greater than 0.'),
    unit_cost: z.coerce.number().nonnegative('Cost cannot be negative.'),
});

export const PurchaseOrderCreateSchema = z.object({
  supplier_id: z.string().uuid({ message: "Please select a supplier." }),
  po_number: z.string().min(1, 'PO Number is required.'),
  order_date: z.date(),
  expected_date: z.date().optional().nullable(),
  status: z.enum(['draft', 'sent', 'partial', 'received', 'cancelled']),
  notes: z.string().optional(),
  items: z.array(POItemInputSchema).min(1, 'At least one item is required.'),
});
export type PurchaseOrderCreateInput = z.infer<typeof PurchaseOrderCreateSchema>;

export const PurchaseOrderUpdateSchema = PurchaseOrderCreateSchema.extend({});
export type PurchaseOrderUpdateInput = z.infer<typeof PurchaseOrderUpdateSchema>;


export const ReceiveItemsFormSchema = z.object({
  poId: z.string().uuid(),
  items: z.array(z.object({
    sku: z.string(),
    quantity_to_receive: z.coerce.number().int().min(0, 'Cannot be negative.'),
  })).min(1).refine(items => items.some(item => item.quantity_to_receive > 0), {
    message: 'You must enter a quantity for at least one item to receive.',
  }),
});
export type ReceiveItemsFormInput = z.infer<typeof ReceiveItemsFormSchema>;


// New types for Supplier Catalogs and Reordering
export const SupplierCatalogSchema = z.object({
  id: z.string().uuid(),
  supplier_id: z.string().uuid(),
  sku: z.string(),
  supplier_sku: z.string().nullable(),
  product_name: z.string().nullable(),
  unit_cost: z.number(),
  moq: z.number().int().optional().default(1),
  lead_time_days: z.number().int().nullable(),
  is_active: z.boolean().default(true),
});
export type SupplierCatalog = z.infer<typeof SupplierCatalogSchema>;

export const ReorderRuleSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  sku: z.string(),
  rule_type: z.string().default('manual'),
  min_stock: z.number().int().nullable(),
  max_stock: z.number().int().nullable(),
  reorder_quantity: z.number().int().nullable(),
});
export type ReorderRule = z.infer<typeof ReorderRuleSchema>;

export const ReorderSuggestionSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    current_quantity: z.number(),
    reorder_point: z.number(),
    suggested_reorder_quantity: z.number(),
    supplier_name: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
    unit_cost: z.number().nullable(),
}).transform((data) => ({
    ...data,
    // Provide default values for nullable fields to prevent downstream errors
    supplier_name: data.supplier_name ?? 'Unknown Supplier',
    supplier_id: data.supplier_id ?? null,
    unit_cost: data.unit_cost ?? 0,
}));
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;

export const ChannelFeeSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  channel_name: z.string(),
  percentage_fee: z.number(),
  fixed_fee: z.number(),
  created_at: z.string(),
  updated_at: z.string().nullable(),
});
export type ChannelFee = z.infer<typeof ChannelFeeSchema>;

export const LocationSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  name: z.string(),
  address: z.string().nullable(),
  is_default: z.boolean().default(false),
});
export type Location = z.infer<typeof LocationSchema>;

export const LocationFormSchema = z.object({
  name: z.string().min(2, { message: "Location name must be at least 2 characters." }),
  address: z.string().optional(),
  is_default: z.boolean().optional(),
});
export type LocationFormData = z.infer<typeof LocationFormSchema>;

export const SupplierPerformanceReportSchema = z.object({
    supplier_name: z.string(),
    total_completed_orders: z.coerce.number(),
    on_time_delivery_rate: z.coerce.number(),
    average_delivery_variance_days: z.coerce.number(),
    average_lead_time_days: z.coerce.number(),
});
export type SupplierPerformanceReport = z.infer<typeof SupplierPerformanceReportSchema>;

// Export the generic Integration type
export type { Integration };
