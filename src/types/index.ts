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
  component?: 'deadStockTable' | 'reorderList' | 'supplierPerformanceTable' | 'confirmation';
  componentProps?: Record<string, any>; // Loosened to allow for various component props
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
    contact_info: z.string().email().nullable(),
    address: z.string().nullable(),
    terms: z.string().nullable(),
    account_number: z.string().nullable(),
});
export type Supplier = z.infer<typeof SupplierSchema>;

export const SupplierFormSchema = z.object({
    vendor_name: z.string().min(2, "Supplier name must be at least 2 characters."),
    contact_info: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    address: z.string().optional().nullable(),
    terms: z.string().optional().nullable(),
    account_number: z.string().optional().nullable(),
});
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;


export const DeadStockItemSchema = z.object({
    sku: z.string(),
    product_name: z.string().nullable(),
    quantity: z.coerce.number().default(0),
    cost: z.coerce.number().default(0),
    total_value: z.coerce.number().default(0),
    last_sale_date: z.string().nullable().optional(),
});
export type DeadStockItem = z.infer<typeof DeadStockItemSchema>;


export type Alert = {
    id: string;
    type: 'low_stock' | 'dead_stock' | 'predictive';
    title: string;
    message: string;
    severity: 'warning' | 'info';
    timestamp: string;
    metadata: {
        productId?: string;
        productName?: string;
        currentStock?: number;
        reorderPoint?: number;
        daysOfStockRemaining?: number;
        lastSoldDate?: string | null;
        value?: number;
    };
};

export type DashboardMetrics = {
    totalSalesValue: number;
    totalProfit: number;
    totalInventoryValue: number;
    lowStockItemsCount: number;
    deadStockItemsCount: number;
    totalSkus: number;
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
  predictive_stock_days: z.number().default(7),
  currency: z.string().nullable().optional().default('USD'),
  timezone: z.string().nullable().optional().default('UTC'),
  tax_rate: z.number().nullable().optional().default(0),
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
  price: number | null;
  total_value: number;
  reorder_point: number | null;
  on_order_quantity: number;
  landed_cost?: number | null;
  barcode?: string | null;
  location_id: string | null;
  location_name: string | null;
  monthly_units_sold: number;
  monthly_profit: number;
  version: number;
};

export const InventoryUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
  cost: z.coerce.number().nonnegative('Cost must be a non-negative number.'),
  reorder_point: z.coerce.number().int().nonnegative('Reorder point must be a non-negative integer.').optional().nullable(),
  landed_cost: z.coerce.number().nonnegative('Landed cost must be a non-negative number.').optional().nullable(),
  barcode: z.string().optional().nullable(),
  location_id: z.string().uuid().optional().nullable(),
  version: z.number().int('Version must be an integer.'),
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
    deviation_percentage: z.coerce.number().optional(), // Make sure this is part of the schema if used
    // Added fields for AI explanation
    explanation: z.string().optional(),
    confidence: z.enum(['high', 'medium', 'low']).optional(),
    suggestedAction: z.string().optional(),
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
  tax_rate: z.number().nullable(),
});
export type PurchaseOrderItem = z.infer<typeof PurchaseOrderItemSchema>;

export const PurchaseOrderSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  supplier_id: z.string().uuid().nullable(),
  po_number: z.string(),
  status: z.enum(['draft', 'sent', 'partial', 'received', 'cancelled']).nullable(),
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

// FIX: Separate base schema from transformed schema
export const ReorderSuggestionBaseSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    current_quantity: z.number(),
    reorder_point: z.number(),
    suggested_reorder_quantity: z.number(),
    supplier_name: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
    unit_cost: z.number().nullable(),
    base_quantity: z.number().int().optional(),
    adjustment_reason: z.string().optional(),
    seasonality_factor: z.number().optional(),
    confidence: z.number().optional(),
});

export const ReorderSuggestionSchema = ReorderSuggestionBaseSchema.transform((data) => ({
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
  address: z.string().optional().nullable(),
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

export const InventoryLedgerEntrySchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sku: z.string(),
    created_at: z.string(),
    change_type: z.string(),
    quantity_change: z.number().int(),
    new_quantity: z.number().int(),
    related_id: z.string().uuid().nullable(),
    notes: z.string().nullable(),
});
export type InventoryLedgerEntry = z.infer<typeof InventoryLedgerEntrySchema>;

export const ExportJobSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    requested_by_user_id: z.string().uuid(),
    status: z.enum(['pending', 'processing', 'completed', 'failed']),
    download_url: z.string().url().nullable(),
    expires_at: z.string().datetime({ offset: true }).nullable(),
    created_at: z.string().datetime({ offset: true }),
});
export type ExportJob = z.infer<typeof ExportJobSchema>;

export const CustomerSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  platform: z.string().nullable(),
  external_id: z.string().nullable(),
  customer_name: z.string(),
  email: z.string().email().nullable(),
  total_orders: z.coerce.number().int(),
  total_spent: z.coerce.number(),
  status: z.string().nullable(),
  deleted_at: z.string().nullable(),
  created_at: z.string(),
});
export type Customer = z.infer<typeof CustomerSchema>;

export const CustomerAnalyticsSchema = z.object({
    total_customers: z.number(),
    new_customers_last_30_days: z.number(),
    average_lifetime_value: z.number(),
    repeat_customer_rate: z.number(),
    top_customers_by_spend: z.array(z.object({ name: z.string(), value: z.number() })).nullable().default([]),
    top_customers_by_sales: z.array(z.object({ name: z.string(), value: z.number() })).nullable().default([]),
});
export type CustomerAnalytics = z.infer<typeof CustomerAnalyticsSchema>;

// === Sales Recording ===
export const SaleItemSchema = z.object({
    id: z.string().uuid(),
    sale_id: z.string().uuid(),
    sku: z.string(),
    product_name: z.string(),
    quantity: z.number().int(),
    unit_price: z.number(),
    cost_at_time: z.number().nullable(),
});
export type SaleItem = z.infer<typeof SaleItemSchema>;

export const SaleSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sale_number: z.string(),
    customer_name: z.string().nullable(),
    customer_email: z.string().email().nullable(),
    total_amount: z.number(),
    payment_method: z.string(),
    notes: z.string().nullable(),
    created_at: z.string(),
    created_by: z.string().uuid(),
});
export type Sale = z.infer<typeof SaleSchema>;

export const SaleCreateItemSchema = z.object({
  sku: z.string().min(1),
  product_name: z.string(),
  quantity: z.coerce.number().int().min(1, "Quantity must be at least 1"),
  unit_price: z.coerce.number().min(0),
  cost_at_time: z.coerce.number().min(0).optional().nullable(),
});
export type SaleCreateItemInput = z.infer<typeof SaleCreateItemSchema>;

export const SaleCreateSchema = z.object({
    customer_name: z.string().optional(),
    customer_email: z.string().email().optional().or(z.literal('')),
    payment_method: z.enum(['cash', 'card', 'other']),
    notes: z.string().optional(),
    items: z.array(SaleCreateItemSchema).min(1, 'Sale must have at least one item.'),
});
export type SaleCreateInput = z.infer<typeof SaleCreateSchema>;


// Schemas for AI Flows moved from flow files
export const AnomalyExplanationInputSchema = z.object({
  anomaly: z.custom<Anomaly>(),
  dateContext: z.object({
    dayOfWeek: z.string(),
    month: z.string(),
    season: z.string(),
    knownHoliday: z.string().optional(),
  }),
});
export type AnomalyExplanationInput = z.infer<typeof AnomalyExplanationInputSchema>;

export const AnomalyExplanationOutputSchema = z.object({
  explanation: z.string().describe("A concise, 1-2 sentence explanation for the anomaly."),
  confidence: z.enum(['high', 'medium', 'low']).describe("The confidence level in the explanation."),
  suggestedAction: z.string().optional().describe("A relevant, actionable suggestion for the user, if applicable."),
});
export type AnomalyExplanationOutput = z.infer<typeof AnomalyExplanationOutputSchema>;

export const CsvMappingInputSchema = z.object({
  csvHeaders: z.array(z.string()).describe("The list of column headers from the user's CSV file."),
  sampleRows: z.array(z.record(z.string())).describe("An array of sample rows (as objects) from the CSV to provide data context."),
  expectedDbFields: z.array(z.string()).describe("The list of target database fields we need to map to."),
});
export type CsvMappingInput = z.infer<typeof CsvMappingInputSchema>;

export const CsvMappingOutputSchema = z.object({
  mappings: z.array(z.object({
    csvColumn: z.string().describe("The original column header from the CSV."),
    dbField: z.string().describe("The database field it maps to."),
    confidence: z.number().min(0).max(1).describe("The AI's confidence in this specific mapping."),
  })),
  unmappedColumns: z.array(z.string()).describe("A list of CSV columns that could not be confidently mapped."),
});
export type CsvMappingOutput = z.infer<typeof CsvMappingOutputSchema>;
