
'use server';
/**
 * @fileOverview A Genkit flow to suggest product price optimizations.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getUnifiedInventoryFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';

const PriceOptimizationInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to suggest prices for."),
});

const PriceSuggestionSchema = z.object({
  sku: z.string().describe("The SKU of the product."),
  productName: z.string().describe("The name of the product."),
  currentPrice: z.number().describe("The current selling price in cents."),
  suggestedPrice: z.number().describe("The new suggested selling price in cents."),
  reasoning: z.string().describe("A concise explanation for the suggested price change (e.g., 'High demand, potential for margin increase', 'Slow sales, consider a promotional price')."),
  estimatedImpact: z.string().describe("A brief description of the potential impact on revenue or profit."),
});

const PriceOptimizationOutputSchema = z.object({
  suggestions: z.array(PriceSuggestionSchema),
  analysis: z.string().describe("A high-level summary of the pricing strategy and observations."),
});

const suggestPricesPrompt = ai.definePrompt({
  name: 'suggestPricesPrompt',
  input: {
    schema: z.object({
      products: z.array(z.object({
          sku: z.string(),
          name: z.string(),
          cost: z.number().nullable(), // cost can be null
          price: z.number().nullable(), // in cents
          inventory_quantity: z.number(),
      })),
    }),
  },
  output: { schema: PriceOptimizationOutputSchema },
  prompt: `
    You are an expert e-commerce pricing analyst. Your task is to analyze a list of products and suggest price optimizations to maximize overall profit, not just revenue.

    Product List (prices and costs are in cents):
    {{{json products}}}

    **Your Task:**
    1.  **Analyze Each Product:** For each product, consider its cost, current price, and stock quantity.
        - **High-Margin, Fast-Movers:** If a product is selling well and has a healthy margin, it might sustain a small price increase.
        - **Slow-Movers or High Stock:** If a product has high inventory or is selling slowly, a price decrease could stimulate demand and liquidate stock, even at a lower margin.
        - **Low-Margin Products:** Be cautious about decreasing prices on already low-margin items unless they are significantly overstocked. A small price increase might be necessary to improve profitability.
    2.  **Generate Suggestions:** Create a list of price change suggestions.
        - **Suggest New Price (in cents):** Provide a new integer value for the price.
        - **Provide Reasoning:** Explain *why* you are suggesting the change.
        - **Estimate Impact:** Describe the likely outcome (e.g., "Increased profit per unit," "Higher sales volume, improved cash flow").
    3.  **Provide a Summary:** Write a 1-2 sentence high-level analysis of your overall pricing strategy.
    4.  **Format:** Provide your response in the specified JSON format.
  `,
});

export const suggestPriceOptimizationsFlow = ai.defineFlow(
  {
    name: 'suggestPriceOptimizationsFlow',
    inputSchema: PriceOptimizationInputSchema,
    outputSchema: PriceOptimizationOutputSchema,
  },
  async ({ companyId }) => {
    try {
      // Fetch top 50 products by value to analyze
      const { items: products } = await getUnifiedInventoryFromDB(companyId, { limit: 50 });

      if (products.length < 1) {
        return {
          suggestions: [],
          analysis: "Not enough product data is available to generate price optimization suggestions.",
        };
      }

      // We only need a subset of fields for the AI analysis
      const productSubset = products.map(p => ({
        sku: p.sku,
        name: p.product_title,
        cost: p.cost,
        price: p.price,
        inventory_quantity: p.inventory_quantity
      }));

      const { output } = await suggestPricesPrompt({ products: productSubset });

      if (!output) {
        throw new Error("AI failed to generate price suggestions.");
      }
      
      return output;
    } catch (e) {
      logError(e, { context: `[Price Optimization Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while generating price optimization suggestions.");
    }
  }
);

export const getPriceOptimizationSuggestions = ai.defineTool(
    {
        name: 'getPriceOptimizationSuggestions',
        description: "Analyzes product data to suggest price optimizations to maximize profit. Use this when asked for 'price suggestions', 'how to price my products', or 'price optimization'.",
        inputSchema: PriceOptimizationInputSchema,
        outputSchema: PriceOptimizationOutputSchema
    },
    async (input) => suggestPriceOptimizationsFlow(input)
);
