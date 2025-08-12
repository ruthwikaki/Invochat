// src/schemas/suppliers.ts
import { z } from "zod";

export const SupplierSchema = z.object({
  id: z.string().uuid(),
  name: z.string(),
  email: z.string().email().nullable().optional(),
  phone: z.string().nullable().optional(),
  default_lead_time_days: z.number().int().nonnegative().nullable().optional(),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true }).optional().nullable(),
  company_id: z.string().uuid(),
}).passthrough();


export const SupplierFormSchema = z.object({
    name: z.string().min(2, "Supplier name must be at least 2 characters."),
    email: z.string().email({ message: "Please enter a valid email address."}).nullable().optional().or(z.literal('')),
    phone: z.string().optional().nullable(),
    default_lead_time_days: z.coerce.number().int().optional().nullable(),
    notes: z.string().optional().nullable(),
});

export const SuppliersArraySchema = z.array(SupplierSchema);

export type Supplier = z.infer<typeof SupplierSchema>;
export type SupplierFormData = z.infer<typeof SupplierFormSchema>;