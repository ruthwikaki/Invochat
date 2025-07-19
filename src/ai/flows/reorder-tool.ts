
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting intelligent reorder suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { getReorderSuggestionsFromDB, getHistoricalSalesForSkus, getSettings } from '@/services/database';
import type { ReorderSuggestion } from '@/types';
import { ReorderSuggestionBaseSchema } from '@/types';

// The input for the AI refinement prompt
const ReorderRefinementInputSchema = z.object({
  suggestions: z.array(ReorderSuggestionBaseSchema),
  historicalSales: z.array(z.object({
      sku: z.string(),
      monthly_sales: z.array(z.object({
          month: z.string(),
          total_quantity: z.number(),
      }))
  })),
  currentDate: z.string().describe("The current date in YYYY-MM-DD format, to provide context for seasonality."),
  timezone: z.string().describe("The business's timezone, e.g., 'America/New_York'.")
});

const EnhancedReorderSuggestionSchema = ReorderSuggestionBaseSchema.extend({
    base_quantity: z.number().int().describe("The initial, simple calculated reorder quantity before AI adjustment."),
    adjustment_reason: z.string().describe("A concise explanation for why the reorder quantity was adjusted."),
    seasonality_factor: z.number().describe("A factor from ~0.5 (low season) to ~1.5 (high season) that influenced the adjustment."),
    confidence: z.number().min(0).max(1).describe("The AI's confidence in its seasonal adjustment."),
});

const reorderRefinementPrompt = ai.definePrompt({
    name: 'reorderRefinementPrompt',
    inputSchema: ReorderRefinementInputSchema,
    outputSchema: z.array(EnhancedReorderSuggestionSchema),
    prompt: `
        You are an expert supply chain analyst for an e-commerce business. Your task is to refine a list of automatically-generated reorder suggestions by considering their historical sales data and seasonality.

        Current Date: {{{currentDate}}}
        Business Timezone: {{{timezone}}}

        Here are the initial suggestions based on stock levels and reorder points. The 'suggested_reorder_quantity' is the base quantity you should start with.
        {{{json suggestions}}}

        Here is the historical monthly sales data for these products over the last 24 months:
        {{{json historicalSales}}}

        **Your Task:**
        For each product, analyze its sales trends and adjust the 'suggested_reorder_quantity' based on your findings.

        1.  **Analyze Seasonality:** Using the business timezone, look at the historical sales. Does this product sell more during certain times of the year (e.g., summer for sunglasses, December for toys)?
        2.  **Identify Trends:** Is the product trending up or down in sales over the last few months?
        3.  **Adjust Quantity:**
            - If you detect a strong upcoming seasonal peak or an upward trend, **increase** the 'suggested_reorder_quantity'.
            - If the product is entering its off-season or sales are declining, you may **decrease** it, but never go below a 30-day supply based on recent sales.
        4.  **Provide Reasoning:** For each item, you must provide a concise 'adjustment_reason'. Example: "Increased quantity by 30% for expected summer demand." or "Slight reduction due to post-holiday sales dip."
        5.  **Set Confidence:** Provide a 'confidence' score (0.0 to 1.0) for your adjustment. High confidence for clear patterns (holidays), medium for general trends, low if data is sparse.
        
        **Output Format:**
        Your Final Output MUST be only the refined list of suggestions as a single JSON array, conforming to the output schema.
        - The original 'suggested_reorder_quantity' should be copied to 'base_quantity'.
        - The new, AI-adjusted quantity should be in 'suggested_reorder_quantity'.
        - Fill out 'adjustment_reason', 'seasonality_factor', and 'confidence' for every item.
    `,
});


export const getReorderSuggestions = ai.defineTool(
  {
    name: 'getReorderSuggestions',
    description:
      "Use this tool to get a list of products that should be reordered based on current stock levels, sales velocity, and reorder rules. This is the primary tool for answering any questions about 'what to order' or 'what is running low'.",
    inputSchema: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get suggestions for."),
    }),
    outputSchema: z.array(EnhancedReorderSuggestionSchema),
  },
  async (input): Promise<z.infer<typeof EnhancedReorderSuggestionSchema>[]> => {
    logger.info(`[Reorder Tool] Getting suggestions for company: ${input.companyId}`);
    try {
        // Step 1: Get baseline suggestions from the database
        const baseSuggestions = await getReorderSuggestionsFromDB(input.companyId);

        if (baseSuggestions.length === 0) {
            logger.info(`[Reorder Tool] No baseline suggestions found for company ${input.companyId}. Returning empty array.`);
            return [];
        }

        // Step 2: Get historical sales data and company settings (for timezone)
        const skus = baseSuggestions.map(s => s.sku);
        const [historicalSales, settings] = await Promise.all([
            getHistoricalSalesForSkus(input.companyId, skus),
            getSettings(input.companyId),
        ]);
        
        // Step 3: Call the AI to refine the suggestions
        logger.info(`[Reorder Tool] Refining ${baseSuggestions.length} suggestions with AI.`);
        
        const { output } = await reorderRefinementPrompt({
            suggestions: baseSuggestions,
            historicalSales: historicalSales,
            currentDate: new Date().toISOString().split('T')[0],
            timezone: settings.timezone || 'UTC',
        });

        if (!output) {
            logger.warn('[Reorder Tool] AI refinement did not return an output. Falling back to base suggestions.');
            // Fallback: Add required fields to base suggestions
            return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'AI refinement failed, using base calculation.',
                seasonality_factor: 1.0,
                confidence: 0.1,
            }));
        }

        logger.info(`[Reorder Tool] AI refinement complete. Returning ${output.length} suggestions.`);
        return output;

    } catch (e) {
        logError(e, { context: `[Reorder Tool] Failed to get suggestions for ${input.companyId}` });
        // Throw an error to notify the calling agent of failure
        throw new Error('An error occurred while trying to generate reorder suggestions.');
    }
  }
);
