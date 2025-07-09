

import { z } from 'zod';

// Schema for validating a row from a product CSV.
export const ProductImportSchema = z.object({
  company_id: z.string().uuid(),
  sku: z.string().min(1, 'SKU is required and cannot be empty.'),
  name: z.string().min(1, 'Product Name is required.'),
  cost: z.coerce.number().int('Cost must be an integer (in cents).').nonnegative('Cost cannot be negative.'),
  price: z.coerce.number().int('Price must be an integer (in cents).').nonnegative('Price cannot be negative.').optional().nullable(),
  category: z.string().optional().nullable(),
  barcode: z.string().optional().nullable(),
});

// Schema for validating a row from a suppliers (vendors) CSV.
export const SupplierImportSchema = z.object({
  company_id: z.string().uuid(),
  vendor_name: z.string().min(1, 'Vendor Name is required.'),
  contact_info: z.string().min(1, 'Contact Info is required.'),
  // Optional fields can be empty in the CSV.
  address: z.string().optional().nullable(),
  terms: z.string().optional().nullable(),
  account_number: z.string().optional().nullable(),
});


// Schema for validating a row from a supplier catalog CSV.
export const SupplierCatalogImportSchema = z.object({
  company_id: z.string().uuid(), // This is not a column in the table, but required for context
  supplier_id: z.string().uuid('supplier_id must be a valid UUID.'),
  product_id: z.string().uuid('product_id must be a valid UUID.'),
  supplier_sku: z.string().optional().nullable(),
  unit_cost: z.coerce.number().int().nonnegative('unit_cost cannot be negative (in cents).'),
  moq: z.coerce.number().int().positive().optional().nullable(),
  lead_time_days: z.coerce.number().int().nonnegative().optional().nullable(),
});


// Schema for validating a row from a reorder rules CSV.
export const ReorderRuleImportSchema = z.object({
  company_id: z.string().uuid(),
  product_id: z.string().uuid('product_id must be a valid UUID.'),
  rule_type: z.string().optional().nullable().default('manual'),
  min_stock: z.coerce.number().int().nonnegative().optional().nullable(),
  max_stock: z.coerce.number().int().nonnegative().optional().nullable(),
  reorder_quantity: z.coerce.number().int().positive().optional().nullable(),
});

// Schema for validating a row from a locations CSV.
export const LocationImportSchema = z.object({
    company_id: z.string().uuid(),
    name: z.string().min(1, 'Location Name is required.'),
    address: z.string().optional().nullable(),
    is_default: z.coerce.boolean().optional().default(false),
});
