
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting intelligent reorder suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { logError } from '@/lib/error-handler';
import { getReorderSuggestionsFromDB, getSettings, getHistoricalSalesForSkus } from '@/services/database';
import type { ReorderSuggestion } from '@/schemas/reorder';
import { EnhancedReorderSuggestionSchema, ReorderSuggestionBaseSchema } from '@/schemas/reorder';
import { config } from '@/config/app-config';

// The input for the AI refinement prompt, derived from the base schema
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

// A more permissive schema for the direct AI output.
// The AI is only responsible for a subset of fields.
const LLMRefinedSuggestionSchema = z.object({
    sku: z.string(),
    suggested_reorder_quantity: z.number().int(),
    adjustment_reason: z.string().nullable().optional(),
    seasonality_factor: z.number().nullable().optional(),
    confidence: z.number().nullable().optional(),
}).passthrough();


export const reorderRefinementPrompt = ai.definePrompt({
    name: 'reorderRefinementPrompt',
    input: { schema: ReorderRefinementInputSchema },
    output: { schema: z.array(LLMRefinedSuggestionSchema) },
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
        const baseSuggestions: ReorderSuggestion[] = await getReorderSuggestionsFromDB(input.companyId);

        if (baseSuggestions.length === 0) {
            logger.info(`[Reorder Tool] No baseline suggestions found for company ${input.companyId}. Returning empty array.`);
            return [];
        }

        // Check if we're in test mode or AI is mocked
        const isMocked = process.env.MOCK_AI === 'true' || process.env.NODE_ENV === 'test';
        
        if (isMocked) {
            logger.info('[Reorder Tool] Using mocked AI response for test environment');
            // Return properly formatted mock data
            return baseSuggestions.map(base => ({
                ...base,
                suggested_reorder_quantity: base.suggested_reorder_quantity || 50,
                base_quantity: base.suggested_reorder_quantity || 50,
                adjustment_reason: 'Test mode - using baseline calculation',
                seasonality_factor: 1.0,
                confidence: 0.8,
            }));
        }
        
        const suggestionsForAI = baseSuggestions.map(s => ({
            ...s,
            current_stock: s.current_quantity,
        }));

        const skus = baseSuggestions.map(s => s.sku);
        const [historicalSales, settings] = await Promise.all([
            getHistoricalSalesForSkus(input.companyId, skus.slice(0, 100)),
            getSettings(input.companyId),
        ]);

        if (!settings.timezone) {
            logger.warn(`[Reorder Tool] Company timezone not set. Defaulting to UTC for AI analysis.`);
        }

        logger.info(`[Reorder Tool] Refining ${baseSuggestions.length} suggestions with AI.`);
        let refinedOutput: z.infer<typeof LLMRefinedSuggestionSchema>[] = [];
        try {
            const { output } = await reorderRefinementPrompt({
                suggestions: suggestionsForAI,
                historicalSales: historicalSales as any,
                currentDate: new Date().toISOString().split('T')[0],
                timezone: settings.timezone || 'UTC',
            }, { model: config.ai.model });

            if(output) {
                refinedOutput = output;
            } else {
                 logger.warn('[Reorder Tool] AI refinement did not return an output. Falling back to base suggestions.');
            }
        } catch (e) {
            logError(e, { context: 'AI refinement prompt failed. Falling back to base suggestions.'});
            // If AI fails, refinedOutput remains empty, and we fall back to base suggestions.
        }

        // Merge AI refinements with the source-of-truth base suggestions
        const refinedSuggestionsMap = new Map(refinedOutput.map(s => [s.sku, s]));

        const mergedSuggestions = baseSuggestions.map(base => {
            const refinement = refinedSuggestionsMap.get(base.sku);
            const seasonality = refinement?.seasonality_factor ?? 1;
            const confidence = refinement?.confidence ?? 0.5;
            const reason = refinement?.adjustment_reason ?? "Using baseline heuristic.";
            const rawQty = Math.round(
                (refinement?.suggested_reorder_quantity ?? base.suggested_reorder_quantity) * seasonality
            );
            return {
                ...base,
                suggested_reorder_quantity: rawQty,
                seasonality_factor: seasonality,
                confidence,
                adjustment_reason: reason,
            };
        });
        
        // Final validation against the strict schema
        const validationResult = z.array(EnhancedReorderSuggestionSchema).safeParse(mergedSuggestions);

        if (!validationResult.success) {
            logError(validationResult.error, { context: 'Final validation of merged reorder suggestions failed. Returning base suggestions.' });
            return baseSuggestions.map(s => ({
                ...s,
                base_quantity: s.suggested_reorder_quantity,
                adjustment_reason: 'AI output was malformed, using base calculation.',
                seasonality_factor: 1.0,
                confidence: 0.0,
            }));
        }

        return validationResult.data;

    } catch (e: unknown) {
        logError(e, { context: `[Reorder Tool] Failed to get suggestions for ${input.companyId}` });
        throw new Error('An error occurred while trying to generate reorder suggestions.');
    }
  }
);
