

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
  visualization?: {
    type: 'table' | 'chart' | 'alert' | 'none';
    data: Record<string, unknown>[];
    config?: {
        title?: string;
        [key: string]: unknown;
    };
  } | null;
  component?: string | null;
  componentProps?: Record<string, any> | null;
  created_at: string;
  confidence?: number | null;
  assumptions?: string[] | null;
  isError?: boolean;
};

export const ProductSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sku: z.string(),
    name: z.string(),
    category: z.string().nullable(),
    price: z.number().int().nullable(), // in cents
    cost: z.number().int(), // in cents
    barcode: z.string().nullable(),
    created_at: z.string(),
    updated_at: z.string().nullable(),
});
export type Product = z.infer<typeof ProductSchema>;

export const ProductUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
  price: z.coerce.number().int().nonnegative('Price must be a non-negative integer (in cents).').optional().nullable(),
  cost: z.coerce.number().int().nonnegative('Cost must be a non-negative integer (in cents).').optional().nullable(),
  barcode: z.string().optional().nullable(),
});
export type ProductUpdateData = z.infer<typeof ProductUpdateSchema>;

export const InventorySchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    product_id: z.string().uuid(),
    quantity: z.number().int(),
    reorder_point: z.number().int().nullable(),
    reorder_quantity: z.number().int().nullable(),
    last_sold_date: z.string().nullable(),
    deleted_at: z.string().nullable(),
    deleted_by: z.string().uuid().nullable(),
    created_at: z.string(),
    updated_at: z.string().nullable(),
});
export type Inventory = z.infer<typeof InventorySchema>;

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

export const SaleItemSchema = z.object({
    id: z.string().uuid(),
    sale_id: z.string().uuid(),
    company_id: z.string().uuid(),
    product_id: z.string().uuid(),
    product_name: z.string(),
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
    customer_email: z.string().nullable(),
    total_amount: z.number().int(), // In cents
    payment_method: z.string(),
    notes: z.string().nullable(),
    created_at: z.string(),
});
export type Sale = z.infer<typeof SaleSchema>;

export const SaleCreateItemSchema = z.object({
  product_id: z.string().uuid(),
  product_name: z.string(),
  quantity: z.coerce.number().int().min(1, "Quantity must be at least 1"),
  unit_price: z.coerce.number().min(0),
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

export const CustomerSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  customer_name: z.string(),
  email: z.string().email().nullable(),
  created_at: z.string(),
  total_orders: z.coerce.number().int(),
  total_spent: z.coerce.number(),
});
export type Customer = z.infer<typeof CustomerSchema>;

export const CompanySettingsSchema = z.object({
  company_id: z.string().uuid(),
  dead_stock_days: z.number().default(90),
  fast_moving_days: z.number().default(30),
  predictive_stock_days: z.number().default(7),
  overstock_multiplier: z.number().default(3),
  high_value_threshold: z.number().default(100000),
  promo_sales_lift_multiplier: z.number().default(2.5),
  currency: z.string().nullable().optional().default('USD'),
  timezone: z.string().nullable().optional().default('UTC'),
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
    supplier_name: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
    barcode: z.string().nullable(),
});
export type UnifiedInventoryItem = z.infer<typeof UnifiedInventoryItemSchema>;

export const ReorderSuggestionBaseSchema = z.object({
    product_id: z.string().uuid(),
    sku: z.string(),
    product_name: z.string(),
    current_quantity: z.number().int(),
    reorder_point: z.number().int(),
    suggested_reorder_quantity: z.number().int(),
    supplier_id: z.string().uuid().nullable(),
    supplier_name: z.string().nullable(),
    unit_cost: z.number().int().nullable(),
    base_quantity: z.number().int().optional(), // Adding this for the AI to know the original
});

export const ReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
    base_quantity: z.number().int().describe("The initial, simple calculated reorder quantity before AI adjustment."),
    adjustment_reason: z.string().describe("A concise explanation for why the reorder quantity was adjusted."),
    seasonality_factor: z.number().describe("A factor from ~0.5 (low season) to ~1.5 (high season) that influenced the adjustment."),
    confidence: z.number().min(0).max(1).describe("The AI's confidence in its seasonal adjustment."),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;


export const DeadStockItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity: z.number().int(),
    total_value: z.number(),
    last_sale_date: z.string().datetime({ offset: true }).nullable(),
});
export type DeadStockItem = z.infer<typeof DeadStockItemSchema>;

export const SupplierPerformanceReportSchema = z.object({
    supplier_name: z.string(),
    total_profit: z.number(),
    avg_margin: z.number(),
    sell_through_rate: z.number(),
});
export type SupplierPerformanceReport = z.infer<typeof SupplierPerformanceReportSchema>;


export const AlertSchema = z.object({
    id: z.string(),
    type: z.enum(['low_stock', 'dead_stock', 'predictive', 'profit_warning']),
    title: z.string(),
    message: z.string(),
    severity: z.enum(['info', 'warning', 'critical']),
    timestamp: z.string().datetime({ offset: true }),
    metadata: z.record(z.any())
});
export type Alert = z.infer<typeof AlertSchema>;


export const AnomalySchema = z.object({
    id: z.string().optional(),
    date: z.string(),
    anomaly_type: z.string(),
    daily_revenue: z.number().optional().nullable(),
    avg_revenue: z.number().optional().nullable(),
    daily_customers: z.number().int().optional().nullable(),
    avg_customers: z.number().int().optional().nullable(),
    deviation_percentage: z.number(),
    explanation: z.string().optional(),
    confidence: z.enum(['high', 'medium', 'low']).optional(),
    suggestedAction: z.string().optional(),
});
export type Anomaly = z.infer<typeof AnomalySchema>;

export const AnomalyExplanationInputSchema = z.object({
    anomaly: AnomalySchema.omit({ explanation: true, confidence: true, suggestedAction: true, id: true }),
    dateContext: z.object({
        dayOfWeek: z.string(),
        month: z.string(),
        season: z.string(),
        knownHoliday: z.string().optional(),
    }),
});
export type AnomalyExplanationInput = z.infer<typeof AnomalyExplanationInputSchema>;

export const AnomalyExplanationOutputSchema = z.object({
    explanation: z.string(),
    confidence: z.enum(['high', 'medium', 'low']),
    suggestedAction: z.string(),
});
export type AnomalyExplanationOutput = z.infer<typeof AnomalyExplanationOutputSchema>;


export const InventoryAnalyticsSchema = z.object({
  total_inventory_value: z.number().default(0),
  total_skus: z.number().int().default(0),
  low_stock_items: z.number().int().default(0),
  potential_profit: z.number().default(0),
});
export type InventoryAnalytics = z.infer<typeof InventoryAnalyticsSchema>;


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
    salesTrendData: { date: string, Sales: number }[];
    inventoryByCategoryData: { name: string, value: number }[];
    topCustomersData: { name: string, value: number }[];
}


export type TeamMember = {
  id: string;
  email: string;
  role: 'Owner' | 'Admin' | 'Member';
};


export const SalesAnalyticsSchema = z.object({
  total_revenue: z.number().default(0),
  average_sale_value: z.number().default(0),
  payment_method_distribution: z.array(z.object({ name: z.string(), value: z.number() })),
});
export type SalesAnalytics = z.infer<typeof SalesAnalyticsSchema>;


export const CustomerAnalyticsSchema = z.object({
    total_customers: z.number().int(),
    new_customers_last_30_days: z.number().int(),
    repeat_customer_rate: z.number(),
    average_lifetime_value: z.number(),
    top_customers_by_spend: z.array(z.object({ name: z.string(), value: z.number() })),
    top_customers_by_sales: z.array(z.object({ name: z.string(), value: z.number() })),
});
export type CustomerAnalytics = z.infer<typeof CustomerAnalyticsSchema>;

export const CsvMappingInputSchema = z.object({
    csvHeaders: z.array(z.string()),
    sampleRows: z.array(z.record(z.string(), z.unknown())),
    expectedDbFields: z.array(z.string()),
});
export type CsvMappingInput = z.infer<typeof CsvMappingInputSchema>;

export const CsvMappingOutputSchema = z.object({
    mappings: z.array(z.object({
        csvColumn: z.string(),
        dbField: z.string(),
        confidence: z.number().min(0).max(1),
    })),
    unmappedColumns: z.array(z.string()),
});
export type CsvMappingOutput = z.infer<typeof CsvMappingOutputSchema>;

export type HealthCheckResult = {
    healthy: boolean;
    metric: number;
    message: string;
}

export const InventoryAgingReportItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity: z.number().int(),
    total_value: z.number(), // in cents
    days_since_last_sale: z.number().int(),
});
export type InventoryAgingReportItem = z.infer<typeof InventoryAgingReportItemSchema>;


export const InventoryLedgerEntrySchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    product_id: z.string().uuid(),
    change_type: z.string(),
    quantity_change: z.number().int(),
    new_quantity: z.number().int(),
    created_at: z.string(),
    related_id: z.string().uuid().nullable(),
    notes: z.string().nullable(),
});
export type InventoryLedgerEntry = z.infer<typeof InventoryLedgerEntrySchema>;

export const ChannelFeeSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    channel_name: z.string(),
    percentage_fee: z.number(),
    fixed_fee: z.number(), // in cents
});
export type ChannelFee = z.infer<typeof ChannelFee>;

export const ProductLifecycleAnalysisSchema = z.object({
    summary: z.object({
        launch_count: z.number().int(),
        growth_count: z.number().int(),
        maturity_count: z.number().int(),
        decline_count: z.number().int(),
    }),
    products: z.array(z.any()),
});
export type ProductLifecycleAnalysis = z.infer<typeof ProductLifecycleAnalysis>;

export const InventoryRiskItemSchema = z.object({
  sku: z.string(),
  product_name: z.string(),
  risk_score: z.number(),
  risk_level: z.string(),
  total_value: z.number(),
  reason: z.string(),
});
export type InventoryRiskItem = z.infer<typeof InventoryRiskItemSchema>;

export const CustomerSegmentAnalysisItemSchema = z.object({
    segment: z.string(),
    sku: z.string(),
    product_name: z.string(),
    total_quantity: z.coerce.number().int(),
    total_revenue: z.coerce.number().int(),
});
export type CustomerSegmentAnalysisItem = z.infer<typeof CustomerSegmentAnalysisItemSchema>;

export const ExportJobSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  requested_by_user_id: z.string().uuid(),
  status: z.string(),
  download_url: z.string().nullable(),
  expires_at: z.string().datetime({ offset: true }).nullable(),
  created_at: z.string().datetime({ offset: true }),
});
export type ExportJob = z.infer<typeof ExportJobSchema>;

export const BusinessProfileSchema = z.object({
  total_revenue_last_12_months: z.number(),
  total_cogs_last_12_months: z.number(),
  total_inventory_value: z.number(),
  product_category_count: z.number().int(),
});
export type BusinessProfile = z.infer<typeof BusinessProfileSchema>;
