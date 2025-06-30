
import { z } from 'zod';

// Schema for validating a row from an inventory CSV.
// It uses `z.coerce` to automatically convert string values from the CSV
// into the correct number types, which is essential for data validation.
export const InventoryImportSchema = z.object({
  sku: z.string().min(1, 'SKU is required and cannot be empty.'),
  name: z.string().min(1, 'Product Name is required.'),
  quantity: z.coerce.number().int('Quantity must be a whole number.').nonnegative('Quantity cannot be negative.'),
  cost: z.coerce.number().nonnegative('Cost cannot be negative.'),
  reorder_point: z.coerce.number().int().nonnegative().optional().nullable(),
  category: z.string().optional().nullable(),
  last_sold_date: z.coerce.date().optional().nullable(),
});

// Schema for validating a row from a suppliers (vendors) CSV.
export const SupplierImportSchema = z.object({
  vendor_name: z.string().min(1, 'Vendor Name is required.'),
  contact_info: z.string().min(1, 'Contact Info is required.'),
  // Optional fields can be empty in the CSV.
  address: z.string().optional().nullable(),
  terms: z.string().optional().nullable(),
  account_number: z.string().optional().nullable(),
});
