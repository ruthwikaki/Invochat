
'use server';
/**
 * @fileOverview A Genkit flow to generate a markdown/clearance plan for dead stock.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getDeadStockReport } from './dead-stock-tool';
import { logError } from '@/lib/error-handler';

const MarkdownInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to generate a markdown plan for."),
});

const MarkdownPhaseSchema = z.object({
  phase: z.number().int().describe("The phase number of the markdown (e.g., 1, 2, 3)."),
  discountPercentage: z.number().describe("The percentage discount for this phase (e.g., 20 for 20%)."),
  durationDays: z.number().int().describe("How many days this phase should last."),
  expectedSellThrough: z.number().describe("The expected percentage of remaining stock to be sold during this phase."),
});

const MarkdownSuggestionSchema = z.object({
  sku: z.string().describe("The SKU of the product."),
  productName: z.string().describe("The name of the product."),
  currentStock: z.number().int().describe("The current quantity on hand."),
  totalValue: z.number().describe("The total value of the current stock at its original cost."),
  markdownStrategy: z.array(MarkdownPhaseSchema).describe("A multi-phase plan to sell off the stock."),
});

const MarkdownOutputSchema = z.object({
  suggestions: z.array(MarkdownSuggestionSchema),
  analysis: z.string().describe("A high-level summary of the markdown strategy and its expected financial impact."),
});

const markdownOptimizerPrompt = ai.definePrompt({
  name: 'markdownOptimizerPrompt',
  input: z.object({
    deadStockItems: z.array(z.object({
        sku: z.string(),
        product_name: z.string(),
        quantity: z.number().int(),
        total_value: z.number(),
        last_sale_date: z.string().nullable(),
    })),
  }),
  output: { schema: MarkdownOutputSchema },
  prompt: `
    You are an expert inventory liquidator and markdown strategist for an e-commerce business. Your task is to analyze a list of dead stock items and create a practical, phased markdown plan to sell them off while maximizing capital recovery.

    Dead Stock List:
    {{{json deadStockItems}}}

    **Your Task:**
    1.  **Analyze Each Item:** For each dead stock item, consider its quantity and total value. Higher value items may require a more cautious, multi-phase approach, while lower value items can be cleared more aggressively.
    2.  **Design a Markdown Strategy:** Create a 2-3 phase markdown plan for each item.
        *   **Phase 1:** Start with a modest discount (e.g., 15-25%) to attract price-sensitive buyers without giving away too much margin.
        *   **Phase 2:** After a set duration (e.g., 14 days), increase the discount (e.g., 40-50%) for remaining stock.
        *   **Phase 3 (Optional):** For stubborn items, a final, deep discount (e.g., 70% or more) or a "bundle with best-seller" suggestion might be needed.
    3.  **Estimate Sell-Through:** For each phase, estimate the percentage of the *then-remaining* stock you expect to sell.
    4.  **Write a Summary:** Provide a high-level analysis of the overall plan. Calculate the total capital tied up in this dead stock and estimate the total expected recovery based on your plan. Mention the overall strategy (e.g., "This plan aims to recover an estimated 45% of the $15,000 tied up in dead stock over the next 6 weeks through a progressive discount model.")
    5.  **Format:** Provide your response in the specified JSON format.
  `,
});

export const markdownOptimizerFlow = ai.defineFlow(
  {
    name: 'markdownOptimizerFlow',
    inputSchema: MarkdownInputSchema,
    outputSchema: MarkdownOutputSchema,
  },
  async ({ companyId }) => {
    try {
      // Step 1: Get the list of dead stock items using the existing tool.
      const deadStockItems = await getDeadStockReport.run({ companyId });

      if (deadStockItems.length < 1) {
        return {
          suggestions: [],
          analysis: "Great news! There is no dead stock to analyze, so no markdown plan is needed.",
        };
      }

      // Step 2: Pass the dead stock data to the AI for the markdown plan.
      const { output } = await markdownOptimizerPrompt({ deadStockItems });

      if (!output) {
        throw new Error("AI failed to generate markdown suggestions.");
      }
      
      return output;
    } catch (e) {
      logError(e, { context: `[Markdown Optimizer Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while generating the markdown optimization plan.");
    }
  }
);

export const getMarkdownSuggestions = ai.defineTool(
    {
        name: 'getMarkdownSuggestions',
        description: "Analyzes dead stock to suggest a multi-phase markdown and clearance plan to liquidate inventory. Use this when asked for 'clearance sale', 'markdown plan', or how to 'get rid of dead stock'.",
        inputSchema: MarkdownInputSchema,
        outputSchema: MarkdownOutputSchema
    },
    async (input) => markdownOptimizerFlow(input)
);
