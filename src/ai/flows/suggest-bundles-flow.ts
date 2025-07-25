
'use server';
/**
 * @fileOverview A Genkit flow to suggest product bundles based on sales data and product categories.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getUnifiedInventoryFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';
import { config } from '@/config/app-config';

const SuggestBundlesInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to suggest bundles for."),
  count: z.number().int().positive().default(5).describe("The number of bundle suggestions to generate."),
});

const BundleSuggestionSchema = z.object({
  bundleName: z.string().describe("A catchy, marketable name for the suggested bundle (e.g., 'Starter Kit', 'Summer Glow Pack')."),
  productSkus: z.array(z.string()).describe("An array of product SKUs that should be included in this bundle."),
  reasoning: z.string().describe("A concise explanation of why these products make a good bundle, referencing either complementary use or sales data."),
  potentialBenefit: z.string().describe("A brief description of the potential business benefit (e.g., 'Increase average order value', 'Move slow-moving accessories')."),
});

const SuggestBundlesOutputSchema = z.object({
  suggestions: z.array(BundleSuggestionSchema),
  analysis: z.string().describe("A high-level summary of the bundling strategy and observations."),
});

const suggestBundlesPrompt = ai.definePrompt({
  name: 'suggestBundlesPrompt',
  input: {
    schema: z.object({
      products: z.array(z.object({
          sku: z.string(),
          name: z.string(),
          category: z.string().nullable(),
      })),
      count: z.number(),
    }),
  },
  output: { schema: SuggestBundlesOutputSchema },
  prompt: `
    You are a merchandising expert for an e-commerce business. Your task is to analyze a list of products and suggest {{count}} compelling product bundles.

    Product List:
    {{{json products}}}

    **Your Task:**
    1.  **Analyze Product Relationships:** Review the product list. Identify products that are complementary (e.g., a coffee maker and coffee filters), belong to the same category, or could be combined to create a "starter pack."
    2.  **Create Bundles:** For each of the {{count}} bundles:
        *   **Select Products:** Choose 2-3 products that would sell well together. Prioritize bundling a high-velocity item with a lower-velocity but high-margin accessory.
        *   **Name the Bundle:** Create a creative, appealing name for the bundle.
        *   **Explain Your Reasoning:** Briefly explain why this bundle makes sense. Is it for a specific use case? Do the products complement each other?
        *   **State the Benefit:** What is the business goal of this bundle? (e.g., "Increase basket size," "Introduce customers to a new product line," "Liquidate slow-moving stock").
    3.  **Provide a Summary:** Write a 1-2 sentence high-level analysis of your overall bundling strategy.
    4.  **Format:** Provide your response in the specified JSON format.
  `,
});

export const suggestBundlesFlow = ai.defineFlow(
  {
    name: 'suggestBundlesFlow',
    inputSchema: SuggestBundlesInputSchema,
    outputSchema: SuggestBundlesOutputSchema,
  },
  async ({ companyId, count }) => {
    try {
      // Fetch a representative sample of products to analyze. We don't need all of them.
      const { items: products } = await getUnifiedInventoryFromDB(companyId, { limit: 200 });

      if (products.length < 2) {
        return {
          suggestions: [],
          analysis: "Not enough product data is available to generate bundle suggestions. Please import more products.",
        };
      }

      // We only need a subset of fields for the AI analysis
      const productSubset = products.map(p => ({
        sku: p.sku,
        name: p.product_title,
        category: p.product_type,
      }));

      const { output } = await suggestBundlesPrompt({ products: productSubset, count }, { model: config.ai.model });

      if (!output) {
        throw new Error("AI failed to generate bundle suggestions.");
      }
      
      return output;
    } catch (e) {
      logError(e, { context: `[Suggest Bundles Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while generating bundle suggestions.");
    }
  }
);

// Define a tool that wraps the flow to make it discoverable by the orchestrator.
export const getBundleSuggestions = ai.defineTool(
    {
        name: 'getBundleSuggestions',
        description: "Analyzes product data to suggest product bundles. Use this when asked for 'bundle ideas', 'product combinations', or how to 'increase average order value'.",
        inputSchema: SuggestBundlesInputSchema,
        outputSchema: SuggestBundlesOutputSchema
    },
    async (input) => suggestBundlesFlow(input)
);
