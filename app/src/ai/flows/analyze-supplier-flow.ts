
'use server';
/**
 * @fileOverview A Genkit flow to analyze supplier performance based on product sales and provide a recommendation.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getSupplierPerformanceFromDB } from '@/services/database';
import type { SupplierPerformanceReport } from '@/types';
import { logError } from '@/lib/error-handler';

const SupplierAnalysisInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to analyze suppliers for."),
});

const SupplierAnalysisOutputSchema = z.object({
  analysis: z.string().describe("A concise, natural-language paragraph summarizing the overall supplier performance and recommending the best one."),
  bestSupplier: z.string().describe("The name of the single best supplier based on the analysis."),
  performanceData: z.array(z.custom<SupplierPerformanceReport>()),
});

const supplierAnalysisPrompt = ai.definePrompt({
  name: 'supplierAnalysisPrompt',
  input: {
    schema: z.object({ performanceData: z.array(z.custom<SupplierPerformanceReport>()) }),
  },
  output: {
    schema: SupplierAnalysisOutputSchema.omit({ performanceData: true }),
  },
  prompt: `
    You are an expert supply chain analyst. You have been given a list of supplier performance reports based on the sales performance of their products. Your task is to analyze this data and provide a recommendation for the most valuable supplier.

    **Supplier Performance Data:**
    {{{json performanceData}}}

    **Your Task:**
    1.  **Analyze:** Review the data. The "best" supplier is a balance of multiple factors:
        *   **Total Profit:** A supplier contributing significantly to profit is very valuable.
        *   **Average Margin:** High margins indicate profitable products.
        *   **Sell-Through Rate:** A high rate indicates their products are in demand and don't become dead stock.
    2.  **Recommend:** Identify the single best supplier based on this financial and sales performance analysis. State their name clearly in the 'bestSupplier' field.
    3.  **Summarize:** Write a concise, 1-2 sentence summary explaining your choice. For example: "While Supplier B provides more products, Supplier A is recommended due to their significantly higher average profit margin (45%) and excellent sell-through rate, making them your most profitable partner."
    4.  **Format:** Provide your response in the specified JSON format.
  `,
});

export const analyzeSuppliersFlow = ai.defineFlow(
  {
    name: 'analyzeSuppliersFlow',
    inputSchema: SupplierAnalysisInputSchema,
    outputSchema: SupplierAnalysisOutputSchema,
  },
  async ({ companyId }) => {
    try {
      // Step 1: Get the raw performance data directly from the service for type safety.
      const performanceData: SupplierPerformanceReport[] = await getSupplierPerformanceFromDB(companyId);

      if (!performanceData || performanceData.length === 0) {
        return {
          analysis: "There is not enough data to analyze supplier performance. Please ensure you have sales data and products assigned to suppliers.",
          bestSupplier: "N/A",
          performanceData: [],
        };
      }

      // Step 2: Pass the data to the AI for analysis and recommendation.
      const { output } = await supplierAnalysisPrompt({ performanceData });
      if (!output) {
        throw new Error("AI analysis of supplier performance failed to return an output.");
      }
      
      return {
        ...output,
        performanceData,
      };
    } catch (e) {
      logError(e, { context: `[Analyze Supplier Flow] Failed for company ${companyId}` });
      throw new Error("An error occurred while analyzing supplier performance.");
    }
  }
);

// We define a tool that is essentially a wrapper around the flow.
// This makes it discoverable by the main orchestrator.
export const getSupplierAnalysisTool = ai.defineTool(
    {
        name: 'getSupplierPerformanceAnalysis',
        description: "Analyzes supplier performance based on sales and profitability to recommend the best one. Use this when the user asks about 'best supplier', 'supplier performance', 'which vendor is best', or 'most profitable supplier'.",
        inputSchema: SupplierAnalysisInputSchema,
        outputSchema: SupplierAnalysisOutputSchema
    },
    async (input) => analyzeSuppliersFlow(input)
);

