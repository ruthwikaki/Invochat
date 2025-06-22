'use server';

/**
 * @fileOverview Supplier Performance AI agent.
 *
 * - getSupplierPerformance - A function that handles the retrieval of supplier performance metrics.
 * - SupplierPerformanceInput - The input type for the getSupplierPerformance function.
 * - SupplierPerformanceOutput - The return type for the getSupplierPerformance function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const SupplierPerformanceInputSchema = z.object({
  query: z.string().describe('The user query about supplier performance.'),
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

export async function getSupplierPerformance(input: SupplierPerformanceInput): Promise<SupplierPerformanceOutput> {
  return supplierPerformanceFlow(input);
}

const getSupplierRanking = ai.defineTool({
  name: 'getSupplierRanking',
  description: 'Retrieves a list of vendors ranked by their on-time delivery performance.',
  inputSchema: z.object({
    query: z.string().describe('The user query about supplier performance.'),
  }),
  outputSchema: z.array(
    z.object({
      vendorName: z.string().describe('The name of the vendor.'),
      onTimeDeliveryRate: z
        .number()
        .describe('The on-time delivery rate of the vendor (0-100).'),
    })
  ),
},
async (input) => {
    const mockData = [
        { vendorName: 'Johnson Supply', onTimeDeliveryRate: 95 },
        { vendorName: 'Acme Corp', onTimeDeliveryRate: 88 },
        { vendorName: 'Global Parts', onTimeDeliveryRate: 92 },
    ];

    // Rank by on-time delivery rate
    const rankedVendors = mockData.sort((a, b) => b.onTimeDeliveryRate - a.onTimeDeliveryRate);

    return rankedVendors;
});

const prompt = ai.definePrompt({
  name: 'supplierPerformancePrompt',
  input: {schema: SupplierPerformanceInputSchema},
  output: {schema: SupplierPerformanceOutputSchema},
  tools: [getSupplierRanking],
  prompt: `You are an AI assistant helping users analyze supplier performance.

  The user has asked the following question: {{{query}}}

  Use the getSupplierRanking tool to retrieve a list of vendors ranked by on-time delivery performance.

  Format the response as a ranked list of vendors, including their names and on-time delivery rates.
  `,
});

const supplierPerformanceFlow = ai.defineFlow(
  {
    name: 'supplierPerformanceFlow',
    inputSchema: SupplierPerformanceInputSchema,
    outputSchema: SupplierPerformanceOutputSchema,
  },
  async input => {
    const {output} = await prompt(input);
    return output!;
  }
);
