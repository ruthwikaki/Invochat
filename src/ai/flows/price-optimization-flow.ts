
'use server';
/**
 * @fileOverview A Genkit flow to suggest product price optimizations.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getUnifiedInventoryFromDB, getHistoricalSalesForSkus } from '@/services/database';
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
          cost: z.number(), // cost is now mandatory
          price: z.number(), // price is now mandatory
          quantity: z.number(),
          sales_last_30_days: z.number(), // Added for better context
      })),
    }),
  },
  output: { schema: PriceOptimizationOutputSchema },
  prompt: `
    You are an expert e-commerce pricing analyst. Your task is to analyze a list of products and suggest price optimizations to maximize overall profit, not just revenue. Prices and costs are in cents.

    Product List with sales context:
    {{{json products}}}

    **Your Task:**
    1.  **Analyze Each Product:** For each product, consider its cost, current price, stock quantity, and recent sales velocity (sales_last_30_days).
        - **Fast-Movers (high sales_last_30_days):** If a product is selling well and has a healthy margin, it might sustain a small price increase (e.g., 5-10%).
        - **Slow-Movers (low or zero sales_last_30_days):** If a product has high inventory or is selling slowly, a price decrease could stimulate demand. Suggest a promotional price.
        - **Low-Margin Products:** Be cautious about decreasing prices on already low-margin items. A small price increase might be necessary if it's a fast-mover.
    2.  **Generate Suggestions:** Create a list of price change suggestions.
        - **Suggest New Price (in cents):** Provide a new integer value for the price. **Crucially, the suggested price MUST be greater than the product's cost.**
        - **Provide Reasoning:** Explain *why* you are suggesting the change, referencing sales velocity.
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
      // Limit to 50 most valuable products to avoid excessive token usage and costs.
      const { items: allProducts } = await getUnifiedInventoryFromDB(companyId, { limit: 50 });

      // Filter out products that are missing critical data for price optimization.
      const validProducts = allProducts.filter(p => p.cost !== null && p.price !== null);
      
      if (validProducts.length < 1) {
        return {
          suggestions: [],
          analysis: "Not enough product data is available to generate price optimization suggestions. Ensure your products have both a cost and a price set.",
        };
      }
      
      const productSkus = validProducts.map(p => p.sku);
      const salesData = await getHistoricalSalesForSkus(companyId, productSkus);
      
      const salesMap = new Map<string, number>();
      if(Array.isArray(salesData)) {
          salesData.forEach(sale => {
              if (sale && typeof sale === 'object' && sale.sku && Array.isArray(sale.monthly_sales)) {
                  const totalSales = sale.monthly_sales.reduce((sum: number, month: any) => sum + (month.total_quantity || 0), 0);
                  salesMap.set(sale.sku, totalSales);
              }
          });
      }


      const productSubsetForAI = validProducts.map(p => ({
        sku: p.sku,
        name: p.product_title,
        cost: p.cost!,
        price: p.price!,
        inventory_quantity: p.inventory_quantity,
        sales_last_30_days: salesMap.get(p.sku) || 0,
      }));

      const { output } = await suggestPricesPrompt({ products: productSubsetForAI });

      if (!output) {
        throw new Error("AI failed to generate price suggestions.");
      }
      
      // Post-processing guardrail: Ensure no suggested price is below cost.
      const finalSuggestions = output.suggestions.map(suggestion => {
          const product = productSubsetForAI.find(p => p.sku === suggestion.sku);
          if (product && suggestion.suggestedPrice < product.cost) {
              // If AI suggests a price below cost, reset it to the current price.
              suggestion.suggestedPrice = suggestion.currentPrice;
              suggestion.reasoning = `[CORRECTED] Original suggestion was below cost. Maintaining current price.`;
          }
          return suggestion;
      });

      return {
          ...output,
          suggestions: finalSuggestions,
      };

    } catch (e) {
      logError(e, { context: `[Price Optimization Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while generating price optimization suggestions.");
    }
  }
);

export const getPriceOptimizationSuggestions = ai.defineTool(
    {
        name: 'getPriceOptimizationSuggestions',
        description: "Analyzes product data to suggest price optimizations to maximize profit. Use this when asked for 'price suggestions', 'how to price my products', or 'price optimization'. Informs the user that it analyzes the top 50 most valuable products.",
        inputSchema: PriceOptimizationInputSchema,
        outputSchema: PriceOptimizationOutputSchema
    },
    async (input) => suggestPriceOptimizationsFlow(input)
);
