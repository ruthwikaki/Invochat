
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting intelligent reorder suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { getReorderSuggestionsFromDB, getHistoricalSalesForSkus } from '@/services/database';
import type { ReorderSuggestion } from '@/types';
import { ReorderSuggestionSchema } from '@/types';

// The input for the AI refinement prompt
const ReorderRefinementInputSchema = z.object({
  suggestions: z.array(ReorderSuggestionSchema),
  historicalSales: z.array(z.object({
      sku: z.string(),
      monthly_sales: z.array(z.object({
          month: z.string(),
          total_quantity: z.number(),
      }))
  })),
  currentDate: z.string().describe("The current date in YYYY-MM-DD format, to provide context for seasonality.")
});

const reorderRefinementPrompt = ai.definePrompt({
    name: 'reorderRefinementPrompt',
    input: { schema: ReorderRefinementInputSchema },
    output: { schema: z.array(ReorderSuggestionSchema) },
    prompt: `
        You are an expert supply chain analyst for an e-commerce business. Your task is to refine a list of automatically-generated reorder suggestions by considering their historical sales data and seasonality.

        Current Date: {{{currentDate}}}

        Here are the initial suggestions based on stock levels and reorder points:
        {{{json suggestions}}}

        Here is the historical monthly sales data for these products over the last 24 months:
        {{{json historicalSales}}}

        Analyze the sales trends for each product.
        - If a product shows a clear upward trend or has strong sales during this time of year (e.g., upcoming holiday, summer season), consider increasing the 'suggested_reorder_quantity'.
        - If a product's sales are declining or it's entering an off-season, you may decrease the 'suggested_reorder_quantity', but do not go below a 30-day supply based on recent average sales.
        - The goal is to avoid stockouts on popular items while preventing overstocking on slow-moving ones.

        Your Final Output MUST be only the refined list of suggestions as a single JSON array, conforming to the output schema. Do not include any other text, reasoning, or explanation.
    `,
});


export const getReorderSuggestions = ai.defineTool(
  {
    name: 'getReorderSuggestions',
    description:
      "Use this tool to get a list of products that should be reordered based on current stock levels, sales velocity, and reorder rules. This is the primary tool for answering any questions about 'what to order' or 'what is running low'.",
    input: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get suggestions for."),
    }),
    output: z.array(ReorderSuggestionSchema),
  },
  async (input): Promise<ReorderSuggestion[]> => {
    logger.info(`[Reorder Tool] Getting suggestions for company: ${input.companyId}`);
    try {
        // Step 1: Get baseline suggestions from the database
        const baseSuggestions = await getReorderSuggestionsFromDB(input.companyId);

        if (baseSuggestions.length === 0) {
            logger.info(`[Reorder Tool] No baseline suggestions found for company ${input.companyId}. Returning empty array.`);
            return [];
        }

        // Step 2: Get historical sales data for these SKUs
        const skusToAnalyze = baseSuggestions.map(s => s.sku);
        const historicalSales = await getHistoricalSalesForSkus(input.companyId, skusToAnalyze);
        
        // Step 3: Call the AI to refine the suggestions
        logger.info(`[Reorder Tool] Refining ${baseSuggestions.length} suggestions with AI.`);
        
        const { output } = await reorderRefinementPrompt({
            suggestions: baseSuggestions,
            historicalSales: historicalSales,
            currentDate: new Date().toISOString().split('T')[0]
        });

        if (!output) {
            logger.warn('[Reorder Tool] AI refinement did not return an output. Falling back to base suggestions.');
            return baseSuggestions;
        }

        logger.info(`[Reorder Tool] AI refinement complete. Returning ${output.length} suggestions.`);
        return output;

    } catch (e) {
        logError(e, { context: `[Reorder Tool] Failed to get suggestions for ${input.companyId}` });
        throw new Error('An error occurred while trying to generate reorder suggestions.');
    }
  }
);
