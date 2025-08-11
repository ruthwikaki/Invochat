

import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';
import { AnomalySchema, AnomalyExplanationInputSchema, AnomalyExplanationOutputSchema, HealthCheckResultSchema } from './ai-schemas';

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
  inventory_quantity: z.number().int().default(0),
  location: z.string().nullable(),
  external_variant_id: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
  reorder_point: z.number().int().nullable(),
  reorder_quantity: z.number().int().nullable(),
  supplier_id: z.string().uuid().nullable().optional(),
});
export type ProductVariant = z.infer<typeof ProductVariantSchema>;

export const UnifiedInventoryItemSchema = ProductVariantSchema.extend({
  product_title: z.string(),
  product_status: z.string().nullable(),
  image_url: z.string().url().nullable(),
  product_type: z.string().nullable(),
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
  name: z.string().nullable(), // name is nullable in db
  email: z.string().email().nullable(),
  total_orders: z.number().int().default(0),
  total_spent: z.number().int().default(0),
  first_order_date: z.string().datetime({ offset: true }).nullable(),
  deleted_at: z.string().datetime({ offset: true }).nullable(),
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
    updated_at: z.string().datetime({ offset: true }).optional().nullable(),
    company_id: z.string().uuid(),
});
export type Supplier = z.infer<typeof SupplierSchema>;

export const PurchaseOrderLineItemSchema = z.object({
  id: z.string().uuid(),
  sku: z.string(),
  product_name: z.string(),
  quantity: z.number().int(),
  cost: z.number().int()
});
export type PurchaseOrderLineItem = z.infer<typeof PurchaseOrderLineItemSchema>;

export const PurchaseOrderLineItemFormSchema = z.object({
  variant_id: z.string().uuid(),
  quantity: z.number().int().positive(),
  cost: z.number().int().nonnegative(),
});

export const PurchaseOrderFormSchema = z.object({
    supplier_id: z.string().uuid("Please select a supplier."),
    status: z.string(),
    expected_arrival_date: z.date().optional(),
    notes: z.string().optional().nullable(),
    line_items: z.array(PurchaseOrderLineItemFormSchema).min(1, "Purchase order must have at least one line item."),
});
export type PurchaseOrderFormData = z.infer<typeof PurchaseOrderFormSchema>;


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

export const PurchaseOrderWithItemsSchema = PurchaseOrderSchema.extend({
    line_items: z.array(PurchaseOrderLineItemSchema),
});
export type PurchaseOrderWithItems = z.infer<typeof PurchaseOrderWithItemsSchema>;

export const PurchaseOrderWithSupplierSchema = PurchaseOrderSchema.extend({
    supplier_name: z.string().nullable(),
});
export type PurchaseOrderWithSupplier = z.infer<typeof PurchaseOrderWithSupplierSchema>;

export const PurchaseOrderWithItemsAndSupplierSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    supplier_id: z.string().uuid().nullable(),
    status: z.string(),
    po_number: z.string(),
    total_cost: z.number().int(),
    expected_arrival_date: z.string().datetime({ offset: true }).nullable(),
    idempotency_key: z.string().uuid().nullable(),
    created_at: z.string().datetime({ offset: true }),
    updated_at: z.string().datetime({ offset: true }).nullable(),
    supplier_name: z.string().nullable(),
    line_items: z.array(z.object({
        id: z.string().uuid(),
        quantity: z.number().int(),
        cost: z.number().int(),
        sku: z.string(),
        product_name: z.string(),
    }))
});

export type PurchaseOrderWithItemsAndSupplier = z.infer<typeof PurchaseOrderWithItemsAndSupplierSchema>;


export const CompanySettingsSchema = z.object({
  company_id: z.string().uuid(),
  dead_stock_days: z.number().int().positive().default(90),
  fast_moving_days: z.number().int().positive().default(30),
  predictive_stock_days: z.number().int().positive().default(7),
  currency: z.string().default('USD'),
  timezone: z.string().default('UTC'),
  tax_rate: z.number().nonnegative().default(0),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
  overstock_multiplier: z.number().int().default(3),
  high_value_threshold: z.number().int().default(100000),
  alert_settings: z.record(z.unknown()).default({}),
});
export type CompanySettings = z.infer<typeof CompanySettingsSchema>;


export type Platform = 'shopify' | 'woocommerce' | 'amazon_fba';

export const IntegrationSyncStatusSchema = z.enum(['syncing_products', 'syncing_sales', 'syncing_orders', 'syncing', 'success', 'failed', 'idle']);

export const IntegrationSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  platform: z.custom<Platform>(),
  shop_domain: z.string().nullable(),
  shop_name: z.string().nullable(),
  is_active: z.boolean(),
  last_sync_at: z.string().nullable(),
  sync_status: IntegrationSyncStatusSchema.nullable(),
  created_at: z.string(),
  updated_at: z.string().nullable(),
});
export type Integration = z.infer<typeof IntegrationSchema>;


export const ConversationSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  company_id: z.string().uuid(),
  title: z.string(),
  created_at: z.string().datetime({ offset: true }),
  last_accessed_at: z.string().datetime({ offset: true }),
  is_starred: z.boolean(),
});
export type Conversation = z.infer<typeof ConversationSchema>;

export const MessageSchema = z.object({
  id: z.string(),
  conversation_id: z.string().uuid(),
  company_id: z.string().uuid(),
  role: z.enum(['user', 'assistant']),
  content: z.string(),
  visualization: z.object({
    type: z.enum(['table', 'chart', 'alert', 'none']),
    data: z.array(z.record(z.string(), z.unknown())),
    config: z.object({
        title: z.string().optional(),
    }).passthrough().optional(),
  }).nullable().optional(),
  component: z.string().nullable().optional(),
  componentProps: z.record(z.string(), z.unknown()).nullable().optional(),
  created_at: z.string().datetime({ offset: true }),
  confidence: z.number().min(0).max(1).nullable().optional(),
  assumptions: z.array(z.string()).nullable().optional(),
  isError: z.boolean().optional(),
});
export type Message = z.infer<typeof MessageSchema>;


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
export type ReorderSuggestionBase = z.infer<typeof ReorderSuggestionBaseSchema>;

export const ReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
    base_quantity: z.number().int(),
    adjustment_reason: z.string(),
    seasonality_factor: z.number(),
    confidence: z.number().min(0).max(1),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;


export const InventoryAgingReportItemSchema = z.object({
  sku: z.string(),
  product_name: z.string(),
  inventory_quantity: z.number(),
  total_value: z.number().int(),
  days_since_last_sale: z.number(),
});
export type InventoryAgingReportItem = z.infer<typeof InventoryAgingReportItemSchema>;

export const InventoryRiskItemSchema = z.object({
    sku: z.string(),
    product_name: z.string(),
    inventory_quantity: z.number(),
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
  total_orders: z.number().int().default(0),
  total_revenue: z.number().int().default(0),
  total_customers: z.number().int().default(0),
  inventory_count: z.number().int().default(0),
  sales_series: z.array(z.object({ date: z.string(), revenue: z.number(), orders: z.number() })).default([]),
  top_products: z.array(z.object({
    product_id: z.string().uuid(),
    product_name: z.string(),
    image_url: z.string().url().nullable(),
    quantity_sold: z.number().int(),
    total_revenue: z.number().int(),
  })).default([]),
  inventory_summary: z.object({
    total_value: z.number().int().default(0),
    in_stock_value: z.number().int().default(0),
    low_stock_value: z.number().int().default(0),
    dead_stock_value: z.number().int().default(0),
  }).default({ total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0 }),
  revenue_change: z.number().default(0),
  orders_change: z.number().default(0),
  customers_change: z.number().default(0),
  dead_stock_value: z.number().int().default(0),
}).passthrough();
export type DashboardMetrics = z.infer<typeof DashboardMetricsSchema>;

export const SalesAnalyticsSchema = z.object({
    total_revenue: z.number().int(),
    total_orders: z.number().int(),
    average_order_value: z.number().int(),
});
export type SalesAnalytics = z.infer<typeof SalesAnalyticsSchema>;

export const InventoryAnalyticsSchema = z.object({
    total_inventory_value: z.number().int(),
    total_products: z.number().int(),
    total_variants: z.number().int(),
    low_stock_items: z.number().int(),
});
export type InventoryAnalytics = z.infer<typeof InventoryAnalyticsSchema>;

export const CustomerAnalyticsSchema = z.object({
    total_customers: z.number().int(),
    new_customers_last_30_days: z.number().int(),
    repeat_customer_rate: z.number(),
    average_lifetime_value: z.number().int(),
    top_customers_by_spend: z.array(z.object({ name: z.string().nullable(), value: z.number().int() })),
    top_customers_by_sales: z.array(z.object({ name: z.string().nullable(), value: z.number().int() })),
});
export type CustomerAnalytics = z.infer<typeof CustomerAnalyticsSchema>;

export { HealthCheckResultSchema };
export type HealthCheckResult = z.infer<typeof HealthCheckResultSchema>;

export { AnomalySchema, AnomalyExplanationInputSchema, AnomalyExplanationOutputSchema };
export type Anomaly = z.infer<typeof AnomalySchema>;
export type AnomalyExplanationInput = z.infer<typeof AnomalyExplanationInputSchema>;
export type AnomalyExplanationOutput = z.infer<typeof AnomalyExplanationOutputSchema>;

export const ChannelFeeSchema = z.object({
  id: z.string().uuid().optional(),
  company_id: z.string().uuid().optional(),
  channel_name: z.string(),
  percentage_fee: z.number().nullable(),
  fixed_fee: z.number().nullable(),
  created_at: z.string().datetime({ offset: true }).optional(),
  updated_at: z.string().datetime({ offset: true }).nullable().optional(),
});
export type ChannelFee = z.infer<typeof ChannelFeeSchema>;

export const CompanyInfoSchema = z.object({
    id: z.string().uuid(),
    name: z.string(),
});
export type CompanyInfo = z.infer<typeof CompanyInfoSchema>;

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


export const SupplierPerformanceReportSchema = z.object({
    supplier_name: z.string(),
    // Profitability Metrics
    total_profit: z.number().int(),
    total_sales_count: z.number(),
    distinct_products_sold: z.number(),
    average_margin: z.number(),
    sell_through_rate: z.number(),
    // Fulfillment Metrics
    on_time_delivery_rate: z.number(),
    average_lead_time_days: z.number().nullable(),
    total_completed_orders: z.number(),
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
  read: z.boolean().optional(),
});
export type Alert = z.infer<typeof AlertSchema>;

export const AuditLogEntrySchema = z.object({
    id: z.string().uuid(),
    created_at: z.string().datetime({ offset: true }),
    user_email: z.string().email().nullable(),
    action: z.string(),
    details: z.record(z.string(), z.unknown()).nullable(),
});
export type AuditLogEntry = z.infer<typeof AuditLogEntrySchema>;

export const FeedbackSchema = z.object({
    id: z.string().uuid(),
    created_at: z.string().datetime({ offset: true }),
    feedback: z.enum(['helpful', 'unhelpful']),
    user_email: z.string().email().nullable(),
    user_message_content: z.string().nullable(),
    assistant_message_content: z.string().nullable(),
});
export type FeedbackWithMessages = z.infer<typeof FeedbackSchema>;
