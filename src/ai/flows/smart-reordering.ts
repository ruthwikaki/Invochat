'use server';

/**
 * @fileOverview Smart Reordering AI agent.
 *
 * - smartReordering - A function that handles the smart reordering process.
 * - SmartReorderingInput - The input type for the smartReordering function.
 * - SmartReorderingOutput - The return type for the smartReordering function.
 */

import {ai} from '@/ai/genkit';
import { getInventoryFromDB } from '@/services/database';
import {z} from 'genkit';

const SmartReorderingInputSchema = z.object({
  query: z
    .string()
    .describe(
      'The query for what to reorder from a supplier.'
    ),
  companyId: z.string().describe("The user's company ID."),
});
export type SmartReorderingInput = z.infer<typeof SmartReorderingInputSchema>;

const SmartReorderingOutputSchema = z.object({
  reorderList: z.array(z.object({
    name: z.string(),
    quantity: z.number(),
    reorder_point: z.number(),
    supplier_name: z.string(),
  })).describe('A list of items that need reordering.'),
});
export type SmartReorderingOutput = z.infer<typeof SmartReorderingOutputSchema>;


const getReorderItemsTool = ai.defineTool({
  name: 'getReorderItems',
  description: 'Retrieves a list of inventory items where the current quantity is below the specified reorder point.',
  inputSchema: z.object({ companyId: z.string() }),
  outputSchema: z.array(z.any()),
}, async ({ companyId }) => {
    const items = await getInventoryFromDB(companyId);
    return items.filter(item => item.quantity < item.reorder_point);
});


const prompt = ai.definePrompt({
  name: 'smartReorderingPrompt',
  input: {schema: SmartReorderingInputSchema},
  output: {schema: SmartReorderingOutputSchema},
  tools: [getReorderItemsTool],
  prompt: `You are an expert inventory manager. A user is asking about what to reorder. Use the getReorderItems tool to find items that are below their reorder point. Then, format the results into the specified output schema. Query: {{{query}}}`,
});

const smartReorderingFlow = ai.defineFlow(
  {
    name: 'smartReorderingFlow',
    inputSchema: SmartReorderingInputSchema,
    outputSchema: SmartReorderingOutputSchema,
  },
  async input => {
    const {output} = await prompt(input);
    if (!output) {
        throw new Error('Could not generate reorder list.');
    }
    return output;
  }
);


export async function smartReordering(input: SmartReorderingInput): Promise<SmartReorderingOutput> {
  return smartReorderingFlow(input);
}
