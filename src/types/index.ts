
import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';
import type { Integration } from '@/features/integrations/types';

export type User = Omit<SupabaseUser, 'app_metadata' | 'role'> & {
  app_metadata?: {
    company_id?: string;
    role?: 'Owner' | 'Admin' | 'Member';
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
    type: 'table' | 'chart' | 'alert' | 'none';
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

export const ProductSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sku: z.string(),
    name: z.string(),
    category: z.string().nullable(),
    barcode: z.string().nullable(),
    created_at: z.string(),
    updated_at: z.string().nullable(),
});
export type Product = z.infer<typeof ProductSchema>;

export const ProductUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
  cost: z.coerce.number().int().nonnegative('Cost must be a non-negative integer (in cents).'),
  price: z.coerce.number().int().nonnegative('Price must be a non-negative integer (in cents).').optional().nullable(),
  barcode: z.string().optional().nullable(),
});
export type ProductUpdateData = z.infer<typeof ProductUpdateSchema>;

export const InventorySchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    product_id: z.string().uuid(),
    quantity: z.number().int(),
    cost: z.number().int(), // in cents
    price: z.number().int().nullable(), // in cents
    landed_cost: z.number().int().nullable(), // in cents
    reorder_point: z.number().int().nullable(),
    last_sold_date: z.string().nullable(),
    version: z.number().int(),
    deleted_at: z.string().nullable(),
    deleted_by: z.string().uuid().nullable(),
    source_platform: z.string().nullable(),
    external_product_id: z.string().nullable(),
    external_variant_id: z.string().nullable(),
    external_quantity: z.number().int().nullable(),
    conflict_status: z.string().nullable(),
    last_external_sync: z.string().nullable(),
    manual_override: z.boolean().default(false),
    expiration_date: z.string().nullable(),
    lot_number: z.string().nullable(),
    created_at: z.string(),
    updated_at: z.string().nullable(),
});
export type Inventory = z.infer<typeof InventorySchema>;

export const InventoryUpdateSchema = z.object({
    name: z.string().min(1, 'Product name is required'),
    category: z.string().nullable(),
    cost: z.coerce.number().nonnegative(),
    price: z.coerce.number().nonnegative().nullable(),
    reorder_point: z.coerce.number().int().nonnegative().nullable(),
    landed_cost: z.coerce.number().nonnegative().nullable(),
    barcode: z.string().nullable(),
    version: z.number().int()
});
export type InventoryUpdateData = z.infer<typeof InventoryUpdateSchema>;

export const SupplierSchema = z.object({
    id: z.string().uuid(),
    name: z.string().min(1),
    email: z.string().email().nullable(),
    phone: z.string().nullable(),
    default_lead_time_days: z.number().int().nullable(),
    notes: z.string().nullable(),
});
export type Supplier = z.infer<typeof SupplierSchema>;

export const SupplierFormSchema = z.object({
    name: z.string().min(2, "Supplier name must be at least 2 characters."),
    email: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    phone: z.string().optional().nullable(),
    default_lead_time_days: z.coerce.number().int().positive().optional().nullable(),
    notes: z.string().optional().nullable(),
});
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;


export const DeadStockItemSchema = z.object({
    sku: z.string(),
    product_name: z.string().nullable(),
    quantity: z.coerce.number().default(0),
    total_value: z.coerce.number().int().default(0),
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
  high_value_threshold: z.number().int().default(100000), // Stored as cents
  fast_moving_days: z.number().default(30),
  predictive_stock_days: z.number().default(7),
  currency: z.string().nullable().optional().default('USD'),
  timezone: z.string().nullable().optional().default('UTC'),
  tax_rate: z.number().nullable().optional().default(0),
  custom_rules: z.record(z.unknown()).nullable().optional(),
  subscription_status: z.string().default('trial'),
  subscription_plan: z.string().default('starter'),
  subscription_expires_at: z.string().nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
  usage_limits: z.record(z.unknown()).nullable(),
  current_usage: z.record(z.unknown()).nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type CompanySettings = z.infer<typeof CompanySettingsSchema>;


export const UnifiedInventoryItemSchema = z.object({
    product_id: z.string().uuid(),
    sku: z.string(),
    product_name: z.string(),
    category: z.string().nullable(),
    quantity: z.number(),
    cost: z.number(), // In cents
    price: z.number().nullable(), // In cents
    total_value: z.number(), // In cents
    reorder_point: z.number().nullable(),
    landed_cost: z.number().nullable(),
    barcode: z.string().nullable(),
    monthly_units_sold: z.number(),
    version: z.number(),
});
export type UnifiedInventoryItem = z.infer<typeof UnifiedInventoryItemSchema>;

export type TeamMember = {
  id: string;
  email: string | undefined;
  role: 'Owner' | 'Admin' | 'Member';
};

export const AnomalySchema = z.object({
    id: z.string().optional(), // Added for unique key prop in React
    date: z.string(),
    daily_revenue: z.coerce.number().int(),
    daily_customers: z.coerce.number().int(),
    avg_revenue: z.coerce.number().int(),
    avg_customers: z.coerce.number().int(),
    anomaly_type: z.string(),
    deviation_percentage: z.coerce.number().optional(),
    explanation: z.string().optional(),
    confidence: z.enum(['high', 'medium', 'low']).optional(),
    suggestedAction: z.string().optional(),
});
export type Anomaly = z.infer<typeof AnomalySchema>;

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
  status: z.string().nullable(),
  deleted_at: z.string().nullable(),
  created_at: z.string(),
  total_orders: z.coerce.number().int().optional(),
  total_spent: z.coerce.number().int().optional(),
});
export type Customer = z.infer<typeof CustomerSchema>;

export const CustomerAnalyticsSchema = z.object({
    total_customers: z.number().nullable(),
    new_customers_last_30_days: z.number().nullable(),
    average_lifetime_value: z.number().int().nullable(), // In cents
    repeat_customer_rate: z.number().nullable(),
    top_customers_by_spend: z.array(z.object({ name: z.string(), value: z.number().int() })).nullable().default([]), // In cents
    top_customers_by_sales: z.array(z.object({ name: z.string(), value: z.number() })).nullable().default([]),
});
export type CustomerAnalytics = z.infer<typeof CustomerAnalyticsSchema>;

export const SaleItemSchema = z.object({
    id: z.string().uuid(),
    sale_id: z.string().uuid(),
    company_id: z.string().uuid(),
    product_id: z.string().uuid(),
    quantity: z.number().int(),
    unit_price: z.number().int(), // In cents
    cost_at_time: z.number().int(), // In cents
});
export type SaleItem = z.infer<typeof SaleItemSchema>;

export const SaleSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sale_number: z.string(),
    customer_name: z.string().nullable(),
    customer_email: z.string().email().nullable(),
    total_amount: z.number().int(), // In cents
    tax_amount: z.number().int().nullable(),
    payment_method: z.string(),
    notes: z.string().nullable(),
    created_at: z.string(),
    created_by: z.string().uuid().nullable(),
});
export type Sale = z.infer<typeof SaleSchema>;

export const SaleCreateItemSchema = z.object({
  product_id: z.string().uuid(),
  product_name: z.string(),
  quantity: z.coerce.number().int().min(1, "Quantity must be at least 1"),
  unit_price: z.coerce.number().min(0),
  location_id: z.string().uuid("Location is required for the sale."),
  max_quantity: z.number().int(),
  min_stock: z.number().int().nullable(),
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

export type InventoryAnalytics = {
    total_inventory_value: number; // In cents
    total_skus: number;
    low_stock_items: number;
    potential_profit: number; // In cents
};

export type SalesAnalytics = {
    total_revenue: number; // In cents
    average_sale_value: number; // In cents
    payment_method_distribution: { name: string; value: number }[];
};

export const BusinessProfileSchema = z.object({
  monthly_revenue: z.number().int().default(0),
  outstanding_po_value: z.number().int().default(0),
  risk_tolerance: z.enum(['conservative', 'moderate', 'aggressive']).default('moderate'),
});
export type BusinessProfile = z.infer<typeof BusinessProfileSchema>;

export const HealthCheckResultSchema = z.object({
    healthy: z.boolean(),
    metric: z.number(),
    message: z.string(),
});
export type HealthCheckResult = z.infer<typeof HealthCheckResultSchema>;

export const InventoryAgingReportItemSchema = z.object({
    product_name: z.string(),
    sku: z.string(),
    days_since_last_sale: z.number().int(),
    quantity: z.number().int(),
    total_value: z.number().int(), // in cents
});
export type InventoryAgingReportItem = z.infer<typeof InventoryAgingReportItemSchema>;
