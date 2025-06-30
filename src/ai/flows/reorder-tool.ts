
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting intelligent reorder suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { getReorderSuggestionsFromDB } from '@/services/database';
import type { ReorderSuggestion } from '@/types';

export const getReorderSuggestions = ai.defineTool(
  {
    name: 'getReorderSuggestions',
    description:
      "Use this tool to get a list of products that should be reordered based on current stock levels, sales velocity, and reorder rules. This is the primary tool for answering any questions about 'what to order' or 'what is running low'.",
    input: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get suggestions for."),
    }),
    output: z.array(z.object({
        sku: z.string(),
        productName: z.string(),
        currentQuantity: z.number(),
        reorderPoint: z.number(),
        suggestedReorderQuantity: z.number(),
        supplierName: z.string(),
        supplierId: z.string().uuid(),
        unitCost: z.number(),
    })),
  },
  async (input): Promise<ReorderSuggestion[]> => {
    logger.info(`[Reorder Tool] Getting suggestions for company: ${input.companyId}`);
    try {
        const suggestions = await getReorderSuggestionsFromDB(input.companyId);
        return suggestions;
    } catch (e) {
        logError(e, { context: `[Reorder Tool] Failed to get suggestions for ${input.companyId}` });
        // In a real scenario, you might want to return a more specific error structure,
        // but for now, an empty array will signal that no suggestions could be generated.
        return [];
    }
  }
);

    