'use server';

/**
 * @fileOverview Supplier Performance AI agent.
 */

import {ai} from '@/ai/genkit';
import { getSuppliersFromDB } from '@/services/database';
import {z} from 'genkit';

const SupplierPerformanceInputSchema = z.object({
  query: z.string().describe('The user query about supplier performance.'),
  companyId: z.string().describe("The user's company ID."),
});
export type SupplierPerformanceInput = z.infer<typeof SupplierPerformanceInputSchema>;

const SupplierPerformanceOutputSchema = z.object({
  rankedVendors: z
    .array(
      z.object({
        vendorName: z.string().describe('The name of the vendor.'),
        onTimeDeliveryRate: z
          .number()
          .describe('The on-time delivery rate of the vendor (0-100).'),
      })
    )
    .describe('A list of vendors ranked by on-time delivery performance.'),
});
export type SupplierPerformanceOutput = z.infer<typeof SupplierPerformanceOutputSchema>;

// Tool to fetch supplier data from our "database".
const getSupplierRankingTool = ai.defineTool({
  name: 'getSupplierRanking',
  description: 'Retrieves a list of vendors ranked by their on-time delivery performance.',
  inputSchema: z.object({ companyId: z.string() }),
  outputSchema: z.array(z.any()),
}, async ({ companyId }) => {
    const suppliers = await getSuppliersFromDB(companyId);
    return suppliers.map(s => ({
        vendorName: s.name,
        onTimeDeliveryRate: s.onTimeDeliveryRate
    }));
});

const prompt = ai.definePrompt({
  name: 'supplierPerformancePrompt',
  input: { schema: SupplierPerformanceInputSchema },
  output: { schema: SupplierPerformanceOutputSchema },
  tools: [getSupplierRankingTool],
  prompt: `You are an expert supply chain analyst. A user is asking about supplier performance. Their query is: {{{query}}}. Use the getSupplierRanking tool to retrieve the information and then format the result to match the output schema.`,
});

const supplierPerformanceFlow = ai.defineFlow(
  {
    name: 'supplierPerformanceFlow',
    inputSchema: SupplierPerformanceInputSchema,
    outputSchema: SupplierPerformanceOutputSchema,
  },
  async (input) => {
    const { output } = await prompt(input);
    if (!output) {
      throw new Error('Failed to get supplier performance data.');
    }
    return output;
  }
);


export async function getSupplierPerformance(input: SupplierPerformanceInput): Promise<SupplierPerformanceOutput> {
  return supplierPerformanceFlow(input);
}
