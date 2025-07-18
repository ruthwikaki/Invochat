import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';

export const UserSchema = z.custom<SupabaseUser>();
export type User = z.infer<typeof UserSchema>;

export const CompanySchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  created_at: z.string().datetime({ offset: true }),
});
export type Company = z.infer<typeof CompanySchema>;

export const TeamMemberSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  role: z.enum(['Owner', 'Admin', 'Member']),
});
export type TeamMember = z.infer<typeof TeamMemberSchema>;


export const ProductSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  title: z.string(),
  description: z.string().nullable(),
  handle: z.string().nullable(),
  product_type: z.string().nullable(),
  tags: z.array(z.string()).nullable(),
  status: z.string().nullable(),
  image_url: z.string().url().nullable(),
  external_product_id: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type Product = z.infer<typeof ProductSchema>;

export const ProductVariantSchema = z.object({
  id: z.string().uuid(),
  product_id: z.string().uuid(),
  company_id: z.string().uuid(),
  sku: z.string(),
  title: z.string().nullable(),
  option1_name: z.string().nullable(),
  option1_value: z.string().nullable(),
  option2_name: z.string().nullable(),
  option2_value: z.string().nullable(),
  option3_name: z.string().nullable(),
  option3_value: z.string().nullable(),
  barcode: z.string().nullable(),
  price: z.number().int().nullable(),
  compare_at_price: z.number().int().nullable(),
  cost: z.number().int().nullable(),
  inventory_quantity: z.number().int(),
  location: z.string().nullable(),
  external_variant_id: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type ProductVariant = z.infer<typeof ProductVariantSchema>;

export const UnifiedInventoryItemSchema = ProductVariantSchema.extend({
  product_title: z.string(),
  product_status: z.string().nullable(),
  image_url: z.string().url().nullable(),
});
export type UnifiedInventoryItem = z.infer<typeof UnifiedInventoryItemSchema>;


export const OrderSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  order_number: z.string(),
  external_order_id: z.string().nullable(),
  customer_id: z.string().uuid().nullable(),
  financial_status: z.string().nullable(),
  fulfillment_status: z.string().nullable(),
  currency: z.string().nullable(),
  subtotal: z.number().int(),
  total_tax: z.number().int().nullable(),
  total_shipping: z.number().int().nullable(),
  total_discounts: z.number().int().nullable(),
  total_amount: z.number().int(),
  source_platform: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type Order = z.infer<typeof OrderSchema>;

export const OrderLineItemSchema = z.object({
  id: z.string().uuid(),
  order_id: z.string().uuid(),
  variant_id: z.string().uuid().nullable(),
  company_id: z.string().uuid(),
  product_name: z.string().nullable(),
  variant_title: z.string().nullable(),
  sku: z.string().nullable(),
  quantity: z.number().int(),
  price: z.number().int(),
  total_discount: z.number().int().nullable(),
  tax_amount: z.number().int().nullable(),
  cost_at_time: z.number().int().nullable(),
  external_line_item_id: z.string().nullable(),
});
export type OrderLineItem = z.infer<typeof OrderLineItemSchema>;

export const RefundSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    order_id: z.string().uuid(),
    refund_number: z.string(),
    status: z.string(),
    reason: z.string().nullable(),
    note: z.string().nullable(),
    total_amount: z.number().int(),
    created_by_user_id: z.string().uuid().nullable(),
    external_refund_id: z.string().nullable(),
    created_at: z.string().datetime({ offset: true }),
});
export type Refund = z.infer<typeof RefundSchema>;


export const CustomerSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  customer_name: z.string().nullable(),
  email: z.string().email().nullable(),
  total_orders: z.number().int(),
  total_spent: z.number().int(),
  first_order_date: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
});
export type Customer = z.infer<typeof CustomerSchema>;


export const SupplierSchema = z.object({
    id: z.string().uuid(),
    name: z.string().min(1),
    email: z.string().email().nullable(),
    phone: z.string().nullable(),
    default_lead_time_days: z.number().int().nullable(),
    notes: z.string().nullable(),
    created_at: z.string().datetime({ offset: true }),
});
export type Supplier = z.infer<typeof SupplierSchema>;

export const PurchaseOrderSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    supplier_id: z.string().uuid().nullable(),
    status: z.string(),
    po_number: z.string(),
    total_cost: z.number().int(),
    expected_arrival_date: z.string().datetime().nullable(),
    idempotency_key: z.string().uuid().nullable(),
    created_at: z.string().datetime({ offset: true }),
});
export type PurchaseOrder = z.infer<typeof PurchaseOrderSchema>;

export const PurchaseOrderWithSupplierSchema = PurchaseOrderSchema.extend({
    supplier_name: z.string().nullable(),
});
export type PurchaseOrderWithSupplier = z.infer<typeof PurchaseOrderWithSupplier>;

export const PurchaseOrderLineItemSchema = z.object({
    id: z.string().uuid(),
    purchase_order_id: z.string().uuid(),
    variant_id: z.string().uuid(),
    quantity: z.number().int(),
    cost: z.number().int(),
});
export type PurchaseOrderLineItem = z.infer<typeof PurchaseOrderLineItemSchema>;


export const CompanySettingsSchema = z.object({
  company_id: z.string().uuid(),
  dead_stock_days: z.number().default(90),
  fast_moving_days: z.number().default(30),
  overstock_multiplier: z.number().default(3),
  high_value_threshold: z.number().default(100000),
  predictive_stock_days: z.number().default(7),
  currency: z.string().default('USD'),
  tax_rate: z.number().default(0),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type CompanySettings = z.infer<typeof CompanySettingsSchema>;


export type Platform = 'shopify' | 'woocommerce' | 'amazon_fba';

export type Integration = {
  id: string;
  company_id: string;
  platform: Platform;
  shop_domain: string | null;
  shop_name: string | null;
  is_active: boolean;
  last_sync_at: string | null;
  sync_status: 'syncing_products' | 'syncing_sales' | 'syncing' | 'success' | 'failed' | 'idle' | null;
  created_at: string;
  updated_at: string | null;
};


export type Conversation = {
  id: string;
  user_id: string;
  company_id: string;
  title: string;
  created_at: string;
  last_accessed_at: string;
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
  componentProps?: Record<string, unknown> | null;
  created_at: string;
  confidence?: number | null;
  assumptions?: string[] | null;
  isError?: boolean;
};


export const SupplierFormSchema = z.object({
    name: z.string().min(2, "Supplier name must be at least 2 characters."),
    email: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    phone: z.string().optional().nullable(),
    default_lead_time_days: z.coerce.number().int().optional().nullable(),
    notes: z.string().optional().nullable(),
});
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;

export const ProductUpdateSchema = z.object({
  title: z.string().min(1, 'Product Title is required.'),
  product_type: z.string().optional().nullable(),
});
export type ProductUpdateData = z.infer<typeof ProductUpdateSchema>;


export const ReorderSuggestionBaseSchema = z.object({
    variant_id: z.string().uuid(),
    product_id: z.string().uuid(),
    sku: z.string(),
    product_name: z.string(),
    supplier_name: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
    current_quantity: z.number().int(),
    suggested_reorder_quantity: z.number().int(),
    unit_cost: z.number().int().nullable(),
});

export const ReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
    base_quantity: z.number().int().optional(),
    adjustment_reason: z.string().nullable().optional(),
    seasonality_factor: z.number().nullable().optional(),
    confidence: z.number().min(0).max(1).nullable().optional(),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;

export const InventoryAgingReportItemSchema = z.object({
  sku: z.string(),
  product_name: z.string(),
  quantity: z.number(),
  total_value: z.number().int(),
  days_since_last_sale: z.number(),
});
export type InventoryAgingReportItem = z.infer<typeof InventoryAgingReportItemSchema>;

export const InventoryRiskItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    quantity: z.number(),
    total_value: z.number().int(),
    risk_score: z.number(),
});
export type InventoryRiskItem = z.infer<typeof InventoryRiskItemSchema>;


export const ProductLifecycleStageSchema = z.object({
  sku: z.string(),
  product_name: z.string(),
  stage: z.enum(['Launch', 'Growth', 'Maturity', 'Decline']),
  total_revenue: z.number().int(),
  total_quantity: z.number(),
  customer_count: z.number(),
});
export type ProductLifecycleStage = z.infer<typeof ProductLifecycleStageSchema>;

export const ProductLifecycleAnalysisSchema = z.object({
    summary: z.object({
        launch_count: z.number(),
        growth_count: z.number(),
        maturity_count: z.number(),
        decline_count: z.number(),
    }),
    products: z.array(ProductLifecycleStageSchema),
});
export type ProductLifecycleAnalysis = z.infer<typeof ProductLifecycleAnalysisSchema>;

export const CustomerSegmentAnalysisItemSchema = z.object({
    segment: z.enum(['New Customers', 'Repeat Customers', 'Top Spenders']),
    sku: z.string(),
    product_name: z.string(),
    total_revenue: z.number().int(),
    total_quantity: z.number(),
    customer_count: z.number(),
});
export type CustomerSegmentAnalysisItem = z.infer<typeof CustomerSegmentAnalysisItemSchema>;

export const DashboardMetricsSchema = z.object({
  total_revenue: z.number().int(),
  revenue_change: z.number(),
  total_sales: z.number(),
  sales_change: z.number(),
  new_customers: z.number(),
  customers_change: z.number(),
  dead_stock_value: z.number().int(),
  sales_over_time: z.array(z.object({
    date: z.string(),
    total_sales: z.number().int(),
  })),
  top_selling_products: z.array(z.object({
    product_name: z.string(),
    total_revenue: z.number().int(),
    image_url: z.string().nullable(),
  })),
  inventory_summary: z.object({
    total_value: z.number().int(),
    in_stock_value: z.number().int(),
    low_stock_value: z.number().int(),
    dead_stock_value: z.number().int(),
  }),
});
export type DashboardMetrics = z.infer<typeof DashboardMetricsSchema>;

export const AnomalySchema = z.object({
    date: z.string(),
    anomaly_type: z.string(),
    daily_revenue: z.number(),
    avg_revenue: z.number(),
    deviation_percentage: z.number(),
});
export type Anomaly = z.infer<typeof AnomalySchema>;

export const HealthCheckResultSchema = z.object({
    healthy: z.boolean(),
    metric: z.number(),
    message: z.string(),
});
export type HealthCheckResult = z.infer<typeof HealthCheckResultSchema>;

export const ChannelFeeSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    channel_name: z.string(),
    fixed_fee: z.number().int().nullable(),
    percentage_fee: z.number().nullable(),
    created_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type ChannelFee = z.infer<typeof ChannelFeeSchema>;

export const CompanyInfoSchema = z.object({
    id: z.string().uuid(),
    name: z.string(),
});
export type CompanyInfo = z.infer<typeof CompanyInfoSchema>;

export type CustomerAnalytics = unknown;

export const InventoryLedgerEntrySchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    variant_id: z.string().uuid(),
    change_type: z.string(),
    quantity_change: z.number().int(),
    new_quantity: z.number().int(),
    related_id: z.string().uuid().nullable(),
    notes: z.string().nullable(),
    created_at: z.string().datetime({ offset: true }),
});
export type InventoryLedgerEntry = z.infer<typeof InventoryLedgerEntrySchema>;


export const CsvMappingInputSchema = z.object({
    csvHeaders: z.array(z.string()),
    sampleRows: z.array(z.record(z.string(), z.unknown())),
    expectedDbFields: z.array(z.string()),
});
export type CsvMappingInput = z.infer<typeof CsvMappingInput>;

export const CsvMappingOutputSchema = z.object({
    mappings: z.array(z.object({
        csvColumn: z.string(),
        dbField: z.string(),
        confidence: z.number().min(0).max(1),
    })),
    unmappedColumns: z.array(z.string()),
});
export type CsvMappingOutput = z.infer<typeof CsvMappingOutputSchema>;

export const DeadStockItemSchema = z.object({
  sku: z.string(),
  product_name: z.string(),
  quantity: z.number().int(),
  total_value: z.number(),
  last_sale_date: z.string().nullable(),
});
export type DeadStockItem = z.infer<typeof DeadStockItemSchema>;


export const AnomalyExplanationInputSchema = z.object({
    anomaly: AnomalySchema,
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
    suggestedAction: z.string().optional(),
});
export type AnomalyExplanationOutput = z.infer<typeof AnomalyExplanationOutputSchema>;

export const SupplierPerformanceReportSchema = z.object({
    supplier_name: z.string(),
    total_profit: z.number().int(),
    total_sales_count: z.number(),
    distinct_products_sold: z.number(),
    average_margin: z.number(),
    sell_through_rate: z.number()
});
export type SupplierPerformanceReport = z.infer<typeof SupplierPerformanceReportSchema>;

export const AlertSchema = z.object({
  id: z.string(),
  type: z.string(),
  title: z.string(),
  message: z.string(),
  severity: z.string(),
  timestamp: z.string(),
  metadata: z.record(z.unknown()),
});
export type Alert = z.infer<typeof AlertSchema>;
