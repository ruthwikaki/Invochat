
'use server';
/**
 * @fileOverview Defines a Genkit tool for creating purchase orders from suggestions.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { createPurchaseOrdersFromSuggestions } from '@/app/data-actions';
import { ReorderSuggestionSchema } from '@/types';

export const createPurchaseOrdersTool = ai.defineTool(
  {
    name: 'createPurchaseOrdersFromSuggestions',
    description:
      "Use this tool to create one or more purchase orders based on a list of reorder suggestions. This should ONLY be used after the user has been presented with suggestions from the `getReorderSuggestions` tool and has confirmed they want to proceed with the order. The suggestions should be taken from the context of the conversation.",
    input: z.object({
      suggestions: z.array(ReorderSuggestionSchema).describe("The list of reorder suggestions to be turned into purchase orders."),
    }),
    output: z.object({
        success: z.boolean(),
        createdPoCount: z.number(),
        error: z.string().optional(),
    }),
  },
  async (input) => {
    logger.info(`[Create PO Tool] Creating POs for ${input.suggestions.length} suggestions.`);
    const result = await createPurchaseOrdersFromSuggestions(input.suggestions);
    return result;
  }
);
