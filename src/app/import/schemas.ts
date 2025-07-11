
import { z } from 'zod';

export const ProductCostImportSchema = z.object({
  company_id: z.string().uuid(),
  sku: z.string().min(1, 'SKU is required and cannot be empty.'),
  cost: z.coerce.number().int('Cost must be an integer (in cents).').nonnegative('Cost cannot be negative.'),
  supplier_name: z.string().optional().nullable(),
  reorder_point: z.coerce.number().int().optional().nullable(),
  reorder_quantity: z.coerce.number().int().optional().nullable(),
  lead_time_days: z.coerce.number().int().optional().nullable(),
});

export const SupplierImportSchema = z.object({
  company_id: z.string().uuid(),
  name: z.string().min(1, 'Supplier Name is required.'),
  email: z.string().email('Invalid email format.'),
  phone: z.string().optional().nullable(),
  default_lead_time_days: z.coerce.number().int().optional().nullable(),
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
