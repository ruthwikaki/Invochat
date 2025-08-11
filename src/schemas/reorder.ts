
'use server';

import { z } from "zod";

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
}).passthrough();
export type ReorderSuggestionBase = z.infer<typeof ReorderSuggestionBaseSchema>;

export const EnhancedReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
    base_quantity: z.number().int().describe("The initial, simple calculated reorder quantity before AI adjustment."),
    adjustment_reason: z.string().describe("A concise explanation for why the reorder quantity was adjusted."),
    seasonality_factor: z.number().describe("A factor from ~0.5 (low season) to ~1.5 (high season) that influenced the adjustment."),
    confidence: z.number().min(0).max(1).describe("The AI's confidence in its seasonal adjustment."),
}).passthrough();
export type EnhancedReorderSuggestion = z.infer<typeof EnhancedReorderSuggestionSchema>;
