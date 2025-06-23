'use server';

/**
 * @fileOverview Supplier Performance AI agent.
 */

import {ai} from '@/ai/genkit';
import { getVendorsFromDB } from '@/services/database';
import {z} from 'genkit';

const SupplierPerformanceInputSchema = z.object({
  query: z.string().describe('The user query about supplier performance.'),
  companyId: z.string().describe("The user's company ID."),
});
export type SupplierPerformanceInput = z.infer<typeof SupplierPerformanceInputSchema>;

const SupplierPerformanceOutputSchema = z.object({
  vendors: z
    .array(
      z.object({
        vendorName: z.string().describe('The name of the vendor.'),
        contactInfo: z.string().describe('The contact information for the vendor.'),
        terms: z.string().describe('The payment terms with the vendor.'),
      })
    )
    .describe('A list of vendors.'),
});
export type SupplierPerformanceOutput = z.infer<typeof SupplierPerformanceOutputSchema>;

// Tool to fetch supplier data from our "database".
const getVendorsTool = ai.defineTool({
  name: 'getVendors',
  description: 'Retrieves a list of all vendors/suppliers.',
  inputSchema: z.object({ companyId: z.string() }),
  outputSchema: z.array(z.any()),
}, async ({ companyId }) => {
    const vendors = await getVendorsFromDB(companyId);
    return vendors.map(v => ({
        vendorName: v.vendor_name,
        contactInfo: v.contact_info,
        terms: v.terms,
    }));
});

const prompt = ai.definePrompt({
  name: 'supplierPerformancePrompt',
  input: { schema: SupplierPerformanceInputSchema },
  output: { schema: SupplierPerformanceOutputSchema },
  tools: [getVendorsTool],
  prompt: `You are an expert supply chain analyst. A user is asking about supplier performance. Their query is: {{{query}}}. Use the getVendors tool to retrieve the vendor information and then format the result to match the output schema.`,
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
