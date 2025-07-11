
import { z } from 'zod';

export const ProductImportSchema = z.object({
  company_id: z.string().uuid(),
  sku: z.string().min(1, 'SKU is required and cannot be empty.'),
  name: z.string().min(1, 'Product Name is required.'),
  cost: z.coerce.number().int('Cost must be an integer (in cents).').nonnegative('Cost cannot be negative.'),
  price: z.coerce.number().int('Price must be an integer (in cents).').nonnegative('Price cannot be negative.').optional().nullable(),
  category: z.string().optional().nullable(),
  barcode: z.string().optional().nullable(),
  reorder_point: z.coerce.number().int().optional().nullable(),
  reorder_quantity: z.coerce.number().int().optional().nullable(),
  supplier_name: z.string().optional().nullable(),
  lead_time_days: z.coerce.number().int().optional().nullable(),
});

export const SupplierImportSchema = z.object({
  company_id: z.string().uuid(),
  supplier_name: z.string().min(1, 'Supplier Name is required.'),
  contact_person: z.string().optional().nullable(),
  email: z.string().email('Invalid email format.').optional().nullable(),
  phone: z.string().optional().nullable(),
  address: z.string().optional().nullable(),
  payment_terms: z.string().optional().nullable(),
  minimum_order_value: z.coerce.number().int().optional().nullable(),
  delivery_days: z.coerce.number().int().optional().nullable(),
  notes: z.string().optional().nullable(),
});

export const HistoricalSalesImportSchema = z.object({
    company_id: z.string().uuid(),
    order_date: z.string().refine(val => !isNaN(Date.parse(val)), { message: "Invalid ISO date format for order_date" }),
    sku: z.string().min(1),
    quantity: z.coerce.number().int().positive(),
    unit_price: z.coerce.number().int().nonnegative(),
    cost_at_time: z.coerce.number().int().nonnegative().optional().nullable(),
    customer_email: z.string().email().optional().nullable(),
    order_id: z.string().optional().nullable(),
});

export const ReorderRuleImportSchema = z.object({
  company_id: z.string().uuid(),
  sku: z.string().min(1),
  min_stock: z.coerce.number().int().nonnegative(),
  max_stock: z.coerce.number().int().nonnegative().optional().nullable(),
  reorder_qty: z.coerce.number().int().positive().optional().nullable(),
  safety_stock_days: z.coerce.number().int().nonnegative().optional().nullable(),
  supplier_name: z.string().optional().nullable(),
  lead_time_override: z.coerce.number().int().nonnegative().optional().nullable(),
});

export const LocationImportSchema = z.object({
    company_id: z.string().uuid(),
    location_name: z.string().min(1, 'Location Name is required.'),
    location_type: z.enum(['warehouse', 'store', 'fulfillment']).optional(),
    address: z.string().optional().nullable(),
    is_default: z.coerce.boolean().optional().default(false),
    sku: z.string().optional().nullable(),
    quantity: z.coerce.number().int().optional().nullable(),
});
