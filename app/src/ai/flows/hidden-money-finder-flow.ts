
'use server';
/**
 * @fileOverview A Genkit flow to find "hidden money" in inventory data.
 * This flow looks for non-obvious opportunities like high-margin slow-movers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getSalesVelocityFromDB, getGrossMarginAnalysisFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';

const HiddenMoneyInputSchema = z.object({
  companyId: z.string().uuid(),
});

const OpportunitySchema = z.object({
  type: z.enum(['High-Margin Slow-Mover', 'Price Increase Candidate', 'Unrealized Profit']),
  sku: z.string(),
  productName: z.string(),
  reasoning: z.string().describe("A concise explanation of why this is a hidden opportunity."),
  suggestedAction: z.string().describe("A clear, actionable next step for the user."),
  potentialValue: z.number().describe("An estimated potential value in cents of this opportunity, if applicable."),
});

const HiddenMoneyOutputSchema = z.object({
  opportunities: z.array(OpportunitySchema),
  analysis: z.string().describe("A high-level summary of the findings and the overall strategy."),
});


const findHiddenMoneyPrompt = ai.definePrompt({
  name: 'findHiddenMoneyPrompt',
  input: {
    schema: z.object({
      slowSellers: z.array(z.any()),
      highMarginProducts: z.array(z.any()),
    }),
  },
  output: { schema: HiddenMoneyOutputSchema },
  prompt: `
    You are an expert business consultant specializing in finding hidden financial opportunities in e-commerce inventory data. Your task is to analyze lists of slow-selling products and high-margin products to identify actionable insights.

    **Data Provided:**
    - Slow Sellers (products that sell infrequently): {{{json slowSellers}}}
    - High Margin Products (products with the best profit margins): {{{json highMarginProducts}}}

    **Your Task:**
    1.  **Cross-Reference Data:** Identify products that appear on BOTH lists. These are "High-Margin Slow-Movers" – your primary target. They don't sell often, but when they do, they are very profitable.
    2.  **Generate Opportunities:** Create a list of opportunities based on your analysis.
        *   For each "High-Margin Slow-Mover", create an opportunity of type 'High-Margin Slow-Mover'.
        *   **Reasoning:** Explain that the product has a strong profit margin but low sales, making it a prime candidate for promotion.
        *   **Suggested Action:** Suggest a specific marketing action, e.g., "Create a targeted ad campaign for this product" or "Feature this product on the homepage."
        *   **Potential Value:** Estimate the potential value. For example, if a product has a $50 margin and you think a campaign could sell 10 more units, the value is 50000 cents.
    3.  **Write Summary Analysis:** Provide a 1-2 sentence high-level summary. Example: "I've identified several products with high profit margins but low sales velocity. A targeted marketing push on these items could significantly boost your overall profit without requiring new inventory."
    4.  **Format:** Provide your response in the specified JSON format.
  `,
});


export const findHiddenMoneyFlow = ai.defineFlow(
  {
    name: 'findHiddenMoneyFlow',
    inputSchema: HiddenMoneyInputSchema,
    outputSchema: HiddenMoneyOutputSchema,
  },
  async ({ companyId }) => {
    try {
      // Step 1: Get the required data using the underlying database functions directly
      const [salesVelocityResult, marginResult] = await Promise.all([
        getSalesVelocityFromDB(companyId, 90, 20),
        getGrossMarginAnalysisFromDB(companyId),
      ]);
      
      const slowSellers = salesVelocityResult?.slow_sellers || [];
      const highMarginProducts = marginResult?.products || [];

      if (slowSellers.length === 0 || highMarginProducts.length === 0) {
        return {
          opportunities: [],
          analysis: "Not enough data to find hidden opportunities. More sales history is needed to analyze slow-movers and high-margin products.",
        };
      }

      // Step 2: Pass the data to the AI for analysis
      const { output } = await findHiddenMoneyPrompt({ slowSellers, highMarginProducts });

      if (!output) {
        throw new Error("AI failed to generate hidden money suggestions.");
      }
      
      return output;
    } catch (e) {
      logError(e, { context: `[Hidden Money Finder Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while finding hidden money opportunities.");
    }
  }
);


export const findHiddenMoney = ai.defineTool(
    {
        name: 'findHiddenMoney',
        description: "Analyzes inventory to find non-obvious financial opportunities, such as high-margin products that are selling slowly. Use when the user asks to 'find hidden money', 'find opportunities', or for 'non-obvious insights'.",
        inputSchema: HiddenMoneyInputSchema,
        outputSchema: HiddenMoneyOutputSchema
    },
    async (input) => findHiddenMoneyFlow(input)
);
