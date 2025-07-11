
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
  created_at: string;
  isError?: boolean;
};

export const ProductSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sku: z.string(),
    name: z.string(),
    category: z.string().nullable(),
    price: z.number().int().nullable(), // in cents
    barcode: z.string().nullable(),
    created_at: z.string(),
    updated_at: z.string().nullable(),
});
export type Product = z.infer<typeof ProductSchema>;

export const ProductUpdateSchema = z.object({
  name: z.string().min(1, 'Product Name is required.'),
  category: z.string().optional().nullable(),
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
    reorder_point: z.number().int().nullable(),
    reorder_quantity: z.number().int().nullable(),
    last_sold_date: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
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
    quantity: z.number().int(),
    unit_price: z.number().int(), // In cents
    cost_at_time: z.number().int(), // In cents
});
export type SaleItem = z.infer<typeof SaleItemSchema>;

export const SaleSchema = z.object({
    id: z.string().uuid(),
    company_id: z.string().uuid(),
    sale_number: z.string(),
    customer_id: z.string().uuid().nullable(),
    total_amount: z.number().int(), // In cents
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
});
export type Customer = z.infer<typeof CustomerSchema>;

export const CompanySettingsSchema = z.object({
  company_id: z.string().uuid(),
  dead_stock_days: z.number().default(90),
  fast_moving_days: z.number().default(30),
  currency: z.string().nullable().optional().default('USD'),
  timezone: z.string().nullable().optional().default('UTC'),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).nullable(),
  subscription_status: z.string().default('trial'),
  subscription_plan: z.string().default('starter'),
  subscription_expires_at: z.string().datetime({ offset: true }).nullable(),
  stripe_customer_id: z.string().nullable(),
  stripe_subscription_id: z.string().nullable(),
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
    reorder_quantity: z.number().nullable(),
    supplier_name: z.string().nullable(),
    supplier_id: z.string().uuid().nullable(),
    last_sold_date: z.string().nullable()
});
export type UnifiedInventoryItem = z.infer<typeof UnifiedInventoryItemSchema>;
