'use server';
/**
 * @fileOverview A Genkit flow to analyze supplier performance and provide a recommendation.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getSupplierPerformanceReport } from './supplier-performance-tool';
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
  inputSchema: z.object({ performanceData: z.array(z.custom<SupplierPerformanceReport>()) }),
  outputSchema: SupplierAnalysisOutputSchema.omit({ performanceData: true }),
  prompt: `
    You are an expert supply chain analyst. You have been given a list of supplier performance reports. Your task is to analyze this data and provide a recommendation for the best supplier.

    **Supplier Performance Data:**
    {{{json performanceData}}}

    **Your Task:**
    1.  **Analyze:** Review the data. The "best" supplier is not always the one with the highest on-time rate. A slightly lower on-time rate might be acceptable if their lead time is significantly shorter. Find a good balance.
    2.  **Recommend:** Identify the single best supplier and state their name clearly in the 'bestSupplier' field.
    3.  **Summarize:** Write a concise, 1-2 sentence summary explaining your choice. For example: "While Supplier B has a perfect on-time record, Supplier A is recommended due to their significantly faster average lead time of 3 days, which improves cash flow."
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
      // Step 1: Get the raw performance data.
      const performanceData = await getSupplierPerformanceReport.run({ companyId });

      if (!performanceData || performanceData.length === 0) {
        return {
          analysis: "There is not enough data to analyze supplier performance. Please ensure you have completed purchase orders in the system.",
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
        description: "Analyzes supplier performance to recommend the best one. Use this when the user asks about 'best supplier', 'supplier performance', 'which vendor is best', 'on-time delivery', or 'supplier reliability'.",
        inputSchema: SupplierAnalysisInputSchema,
        outputSchema: SupplierAnalysisOutputSchema
    },
    async (input) => analyzeSuppliersFlow(input)
);
