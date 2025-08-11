

'use server';
/**
 * @fileOverview Defines a Genkit tool for getting intelligent reorder suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { logError } from '@/lib/error-handler';
import { getReorderSuggestionsFromDB, getSettings, getHistoricalSalesForSkus } from '@/services/database';
import type { ReorderSuggestionBase } from '@/types';
import { EnhancedReorderSuggestionSchema } from '@/schemas/reorder';
import { config } from '@/config/app-config';

// The input for the AI refinement prompt
const ReorderRefinementInputSchema = z.object({
  suggestions: z.array(z.custom<ReorderSuggestionBase>()),
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

export const reorderRefinementPrompt = ai.definePrompt({
    name: 'reorderRefinementPrompt',
    input: { schema: ReorderRefinementInputSchema },
    output: { schema: z.array(EnhancedReorderSuggestionSchema) },
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
            - If the product is entering its off-season or sales are declining, you may **decrease** it.
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
        const baseSuggestions = await getReorderSuggestionsFromDB(input.companyId);

        if (baseSuggestions.length === 0) {
            logger.info(`[Reorder Tool] No baseline suggestions found for company ${input.companyId}. Returning empty array.`);
            return [];
        }

        const skus = baseSuggestions.map(s => s.sku);
        const [historicalSales, settings] = await Promise.all([
            getHistoricalSalesForSkus(input.companyId, skus.slice(0, 100)), // Cap SKUs to prevent excessive token usage
            getSettings(input.companyId),
        ]);
        
        // If no historical sales data, return base suggestions
        if (!historicalSales || historicalSales.length === 0) {
             logger.warn(`[Reorder Tool] No historical sales data for SKUs. Returning base suggestions.`);
             return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'No historical data available for AI refinement.',
                seasonality_factor: 1.0,
                confidence: 0.1,
            }));
        }
        
        if (!settings.timezone) {
            logger.warn(`[Reorder Tool] Company timezone not set. Defaulting to UTC for AI analysis.`);
        }

        logger.info(`[Reorder Tool] Refining ${baseSuggestions.length} suggestions with AI.`);
        
        const { output } = await reorderRefinementPrompt({
            suggestions: baseSuggestions,
            historicalSales: historicalSales as any,
            currentDate: new Date().toISOString().split('T')[0],
            timezone: settings.timezone || 'UTC',
        }, { model: config.ai.model });

        if (!output) {
            logger.warn('[Reorder Tool] AI refinement did not return an output. Falling back to base suggestions.');
            return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'AI refinement failed, using base calculation.',
                seasonality_factor: 1.0,
                confidence: 0.1,
            }));
        }
        
        const validatedOutput = z.array(EnhancedReorderSuggestionSchema).safeParse(output);
        if(!validatedOutput.success) {
            logError(validatedOutput.error, { context: 'AI output failed validation for reorder suggestions' });
            // Fallback to base suggestions if AI output is malformed
            return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'AI output was malformed, using base calculation.',
                seasonality_factor: 1.0,
                confidence: 0.0,
            }));
        }


        logger.info(`[Reorder Tool] AI refinement complete. Applying post-processing guards.`);
        // Post-processing guardrail: ensure we don't suggest ordering less than a 30-day supply.
        const finalSuggestions = validatedOutput.data.map(suggestion => {
            const salesRecord = (historicalSales as any[]).find(s => s.sku === suggestion.sku);
            if (salesRecord && salesRecord.monthly_sales && salesRecord.monthly_sales.length > 0) {
                // Approximate 30-day supply from the most recent month's sales
                const lastMonthSales = salesRecord.monthly_sales[salesRecord.monthly_sales.length - 1].total_quantity || 0;
                if (suggestion.suggested_reorder_quantity < lastMonthSales) {
                    suggestion.suggested_reorder_quantity = lastMonthSales;
                    suggestion.adjustment_reason = `[CORRECTED] Increased to meet minimum 30-day supply based on recent sales.`;
                }
            }
            return suggestion;
        });

        return finalSuggestions;

    } catch (e: unknown) {
        logError(e, { context: `[Reorder Tool] Failed to get suggestions for ${input.companyId}` });
        throw new Error('An error occurred while trying to generate reorder suggestions.');
    }
  }
);
