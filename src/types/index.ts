

import type { ReactNode } from 'react';
import type { User as SupabaseUser } from '@supabase/supabase-js';
import { z } from 'zod';
import type { Integration } from '@/features/integrations/types';

// --- CORE AUTH & COMPANY ---
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


// --- PRODUCT CATALOG ---
export const ProductSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  title: z.string(),
  description: z.string().nullable(),
  handle: z.string().nullable(),
  product_type: z.string().nullable(),
  tags: z.array(z.string()).nullable(),
  status: z.enum(['active', 'draft', 'archived']),
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
  title: z.string(),
  option1_name: z.string().nullable(),
  option1_value: z.string().nullable(),
  option2_name: z.string().nullable(),
  option2_value: z.string().nullable(),
  option3_name: z.string().nullable(),
  option3_value: z.string().nullable(),
  barcode: z.string().nullable(),
  price: z.number().int(), // in cents
  compare_at_price: z.number().int().nullable(),
  cost: z.number().int().nullable(), // in cents
  inventory_quantity: z.number().int(),
  external_variant_id: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
});
export type ProductVariant = z.infer<typeof ProductVariantSchema>;

// Combined type for UI display, including parent product info
export const UnifiedInventoryItemSchema = ProductVariantSchema.extend({
  product_title: z.string(),
  product_status: z.enum(['active', 'draft', 'archived']),
  image_url: z.string().url().nullable(),
});
export type UnifiedInventoryItem = z.infer<typeof UnifiedInventoryItemSchema>;


// --- ORDERS & FULFILLMENT ---
export const OrderSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  order_number: z.string(),
  external_order_id: z.string().nullable(),
  customer_id: z.string().uuid().nullable(),
  status: z.string(),
  financial_status: z.string(),
  fulfillment_status: z.string(),
  currency: z.string(),
  subtotal: z.number().int(),
  total_tax: z.number().int(),
  total_shipping: z.number().int(),
  total_discounts: z.number().int(),
  total_amount: z.number().int(),
  source_platform: z.string().nullable(),
  created_at: z.string().datetime({ offset: true }),
});
export type Order = z.infer<typeof OrderSchema>;

export const OrderLineItemSchema = z.object({
  id: z.string().uuid(),
  order_id: z.string().uuid(),
  variant_id: z.string().uuid(),
  product_id: z.string().uuid(),
  product_name: z.string(),
  variant_title: z.string().nullable(),
  sku: z.string(),
  quantity: z.number().int(),
  price: z.number().int(),
  total_discount: z.number().int(),
  tax_amount: z.number().int(),
  fulfillment_status: z.string(),
  external_line_item_id: z.string().nullable(),
});
export type OrderLineItem = z.infer<typeof OrderLineItemSchema>;


// --- CUSTOMERS ---
export const CustomerSchema = z.object({
  id: z.string().uuid(),
  company_id: z.string().uuid(),
  customer_name: z.string().nullable(),
  email: z.string().email().nullable(),
  total_orders: z.number().int(),
  total_spent: z.number().int(),
  created_at: z.string().datetime({ offset: true }),
});
export type Customer = z.infer<typeof CustomerSchema>;


// --- SUPPLIERS & PURCHASING ---
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


// --- COMPANY SETTINGS ---
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
});
export type CompanySettings = z.infer<typeof CompanySettingsSchema>;


// --- AI & CHAT ---
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


// --- FORMS & ACTIONS ---
export const SupplierFormSchema = z.object({
    name: z.string().min(2, "Supplier name must be at least 2 characters."),
    email: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    phone: z.string().optional().nullable(),
    default_lead_time_days: z.coerce.number().int().optional().nullable(),
    notes: z.string().optional().nullable(),
});
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;

export const ProductUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
  cost: z.coerce.number().int().optional().nullable(),
  price: z.coerce.number().int().optional().nullable(),
  barcode: z.string().optional().nullable(),
  location_note: z.string().optional().nullable(),
});
export type ProductUpdateData = z.infer<typeof ProductUpdateSchema>;


// Schemas for AI flows
export const ReorderSuggestionBaseSchema = z.object({
    variant_id: z.string().uuid(),
    product_id: z.string().uuid(),
    sku: z.string(),
    product_name: z.string(),
    supplier_name: z.string().nullable(),
    current_quantity: z.number().int(),
    suggested_reorder_quantity: z.number().int(),
    reorder_point: z.number().int().nullable(),
    unit_cost: z.number().int().nullable(),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionBaseSchema>;


// Placeholder for Dashboard and other complex types
export type DashboardMetrics = any;
export type InventoryAnalytics = any;
export type SalesAnalytics = any;
export type CustomerAnalytics = any;
export type Alert = any;
export type Anomaly = any;
export type HealthCheckResult = any;
export type InventoryAgingReportItem = any;
export type ProductLifecycleAnalysis = any;
export type InventoryRiskItem = any;
export type CustomerSegmentAnalysisItem = any;
export type ChannelFee = any;
export type BusinessProfile = any;
export type CompanyInfo = any;
export type InventoryLedgerEntry = any;


// CSV mapping types remain the same
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

// Quick sale types will be replaced by the new order schema
export type Sale = any;
export type SaleCreateInput = any;
