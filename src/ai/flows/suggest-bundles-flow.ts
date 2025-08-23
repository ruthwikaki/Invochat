

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
  suggestedPrice: z.number().describe("Recommended bundle price (typically 10-15% discount from individual prices)."),
  estimatedDemand: z.number().describe("Estimated monthly demand for this bundle based on historical data."),
  profitMargin: z.number().describe("Expected profit margin percentage for the bundle."),
  seasonalFactors: z.array(z.string()).describe("Seasonal factors that could affect bundle performance."),
  targetCustomerSegment: z.string().describe("Primary customer segment this bundle targets."),
  crossSellOpportunity: z.number().describe("Potential increase in average order value (percentage)."),
});

const SuggestBundlesOutputSchema = z.object({
  suggestions: z.array(BundleSuggestionSchema),
  analysis: z.string().describe("A high-level summary of the bundling strategy and observations."),
  totalPotentialRevenue: z.number().describe("Total potential monthly revenue from all suggested bundles."),
  implementationRecommendations: z.array(z.string()).describe("Practical recommendations for implementing these bundles."),
});

const suggestBundlesPrompt = ai.definePrompt({
  name: 'suggestBundlesPrompt',
  input: {
    schema: z.object({
      products: z.array(z.object({
          sku: z.string(),
          name: z.string(),
          category: z.string().nullable(),
          price: z.number().optional(),
      })),
      count: z.number(),
    }),
  },
  output: { schema: SuggestBundlesOutputSchema },
  prompt: `
    You are a merchandising expert for an e-commerce business. Your task is to analyze a list of products and suggest {{count}} compelling product bundles that maximize revenue and customer value.

    Product List:
    {{{json products}}}

    **Your Task:**
    1.  **Analyze Product Relationships:** Review the product list. Identify products that are complementary (e.g., a coffee maker and coffee filters), belong to the same category, or could be combined to create a "starter pack."
    2.  **Create Advanced Bundles:** For each of the {{count}} bundles:
        *   **Select Products:** Choose 2-4 products that would sell well together. Prioritize bundling a high-velocity item with a lower-velocity but high-margin accessory.
        *   **Name the Bundle:** Create a creative, appealing name for the bundle.
        *   **Explain Your Reasoning:** Briefly explain why this bundle makes sense. Is it for a specific use case? Do the products complement each other?
        *   **State the Benefit:** What is the business goal of this bundle?
        *   **Price Strategy:** Set a bundle price that's 10-15% less than individual prices combined
        *   **Demand Estimation:** Estimate realistic monthly demand based on product appeal and market size
        *   **Profit Analysis:** Calculate expected profit margin for the bundle
        *   **Seasonal Considerations:** Identify any seasonal factors that could affect performance
        *   **Target Customers:** Define the primary customer segment for this bundle
        *   **Cross-sell Impact:** Estimate the percentage increase in average order value
    3.  **Calculate Total Revenue:** Sum up all potential monthly revenue from bundles
    4.  **Implementation Strategy:** Provide 3-4 practical recommendations for rolling out these bundles
    5.  **Provide Strategic Analysis:** Write a comprehensive analysis of your overall bundling strategy.
    6.  **Format:** Provide your response in the specified JSON format with all required fields.

    Focus on bundles that solve real customer problems, increase order value, and improve inventory turnover.
  `,
});

export const suggestBundlesFlow = ai.defineFlow(
  {
    name: 'suggestBundlesFlow',
    inputSchema: SuggestBundlesInputSchema,
    outputSchema: SuggestBundlesOutputSchema,
  },
  async ({ companyId, count }) => {
    // Mock response for testing to avoid API quota issues
    if (process.env.MOCK_AI === 'true') {
      return {
        suggestions: [
          {
            bundleName: 'Starter Pack Pro',
            productSkus: ['MOCK-WIDGET-001', 'MOCK-ACCESSORY-002'],
            reasoning: 'These products are frequently purchased together and offer complementary functionality for new customers.',
            potentialBenefit: 'Increase average order value by 25% while helping customers get started with a complete solution.',
            suggestedPrice: 89.99,
            estimatedDemand: 120,
            profitMargin: 35.5,
            seasonalFactors: ['Back-to-school', 'New Year'],
            targetCustomerSegment: 'New customers',
            crossSellOpportunity: 25
          },
          {
            bundleName: 'Premium Essentials Bundle',
            productSkus: ['MOCK-PREMIUM-001', 'MOCK-ESSENTIAL-003'],
            reasoning: 'High-margin products that work well together, appealing to customers seeking quality solutions.',
            potentialBenefit: 'Boost profit margins while providing exceptional value to quality-conscious customers.',
            suggestedPrice: 149.99,
            estimatedDemand: 85,
            profitMargin: 42.3,
            seasonalFactors: ['Holiday season', 'Premium product launches'],
            targetCustomerSegment: 'Premium customers',
            crossSellOpportunity: 35
          },
          {
            bundleName: 'Complete Solution Kit',
            productSkus: ['MOCK-BASE-001', 'MOCK-ADDON-002', 'MOCK-SUPPORT-003'],
            reasoning: 'End-to-end solution that addresses customer needs from setup to maintenance.',
            potentialBenefit: 'Reduce customer support needs while maximizing cross-sell opportunities.',
            suggestedPrice: 199.99,
            estimatedDemand: 65,
            profitMargin: 38.7,
            seasonalFactors: ['Business quarters', 'Product lifecycle'],
            targetCustomerSegment: 'Business customers',
            crossSellOpportunity: 45
          }
        ].slice(0, count),
        analysis: "Bundle opportunities focus on complementary products and customer journey stages. Implementing these bundles could increase average order value while providing better customer experience.",
        totalPotentialRevenue: 42497.35,
        implementationRecommendations: [
          "Start with the highest-margin bundle to test market response",
          "Create limited-time offers to drive urgency",
          "Use customer segmentation for targeted bundle marketing",
          "Monitor individual product sell-through rates within bundles"
        ]
      };
    }

    try {
      // Fetch a representative sample of products to analyze. We don't need all of them.
      const { items: products } = await getUnifiedInventoryFromDB(companyId, { limit: 200 });

      if (products.length < 2) {
        return {
          suggestions: [],
          analysis: "Not enough product data is available to generate bundle suggestions. Please import more products.",
          totalPotentialRevenue: 0,
          implementationRecommendations: []
        };
      }

      // We only need a subset of fields for the AI analysis
      const productSubset = products.map(p => ({
        sku: p.sku,
        name: p.product_title,
        category: p.product_type,
        price: (p.price || 0) / 100, // Convert cents to dollars
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


    