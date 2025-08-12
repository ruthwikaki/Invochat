// NOTE: No 'use server' here — this is a pure schema module.
import { z } from 'zod';

export const ReorderSuggestionBaseSchema = z.object({
  product_id: z.string(),
  sku: z.string(),
  product_name: z.string(),
  current_inventory: z.number(),
  avg_daily_sales: z.number(),
  lead_time_days: z.number(),
  safety_stock: z.number(),
  weeks_of_coverage: z.number().nullable().optional(),
  min_order_qty: z.number().nullable().optional().default(0),
  max_order_qty: z.number().nullable(),
  reorder_point: z.number().nullable(),
  suggested_reorder_quantity: z.number().default(0),
});

export const EnhancedReorderSuggestionSchema =
  ReorderSuggestionBaseSchema.extend({
    // treat missing fields as valid; provide sensible defaults
    confidence: z.number().min(0).max(1).optional().default(0),
    seasonality_factor: z.number().positive().optional().default(1),
    adjustment_reason: z.string().optional().default("Using baseline heuristic."),
  });

export const ReorderResponseSchema = z.object({
  suggestions: z.array(EnhancedReorderSuggestionSchema),
});

export type ReorderSuggestionBase = z.infer<typeof ReorderSuggestionBaseSchema>;
export type EnhancedReorderSuggestion = z.infer<typeof EnhancedReorderSuggestionSchema>;
export type ReorderResponse = z.infer<typeof ReorderResponseSchema>;

export const ReorderSuggestionSchema = z.object({
  variant_id: z.string(),
  product_id: z.string(),
  sku: z.string(),
  product_name: z.string(),
  supplier_name: z.string().nullable(),
  supplier_id: z.string().nullable(),
  current_quantity: z.number().int(),
  suggested_reorder_quantity: z.number().int(),
  unit_cost: z.number().int().nullable(),
  base_quantity: z.number().int(),
  adjustment_reason: z.string().nullable(),
  seasonality_factor: z.number().nullable(),
  confidence: z.number().nullable(),
});
export type ReorderSuggestion = z.infer<typeof ReorderSuggestionSchema>;
