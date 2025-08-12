// NOTE: No 'use server' here — this is a pure schema module.
import { z } from 'zod';

export const ReorderSuggestionBaseSchema = z.object({
  product_id: z.string(),
  product_name: z.string(),
  current_stock: z.number().int().min(0),
  lead_time_days: z.number().int().min(0),
  avg_daily_sales: z.number().min(0),
  safety_stock: z.number().int().min(0),
  reorder_point: z.number().int().min(0),
  days_of_stock_remaining: z.number().min(0),
});

export type ReorderSuggestionBase = z.infer<typeof ReorderSuggestionBaseSchema>;

export const EnhancedReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
  recommended_order_qty: z.number().int().min(0),
  rationale: z.string().optional(),
  supplier: z.string().optional(),
  unit_cost: z.number().min(0), // or .int().min(0) if this is in cents
  expected_stockout_date: z.string().optional(),
});

export type EnhancedReorderSuggestion = z.infer<typeof EnhancedReorderSuggestionSchema>;

export const ReorderSuggestionSchema = z.object({
  variant_id: z.string().uuid(),
  product_id: z.string().uuid(),
  sku: z.string(),
  product_name: z.string(),
  supplier_name: z.string().nullable(),
  supplier_id: z.string().uuid().nullable(),
  current_quantity: z.number().int(),
  suggested_reorder_quantity: z.number().int(),
  unit_cost: z.number().int().nullable(),
  base_quantity: z.number().int(),
  adjustment_reason: z.string().nullable(),
  seasonality_factor: z.number().nullable(),
  confidence: z.number().nullable(),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;
