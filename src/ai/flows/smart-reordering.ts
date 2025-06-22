// use server'

/**
 * @fileOverview Smart Reordering AI agent.
 *
 * - smartReordering - A function that handles the smart reordering process.
 * - SmartReorderingInput - The input type for the smartReordering function.
 * - SmartReorderingOutput - The return type for the smartReordering function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const SmartReorderingInputSchema = z.object({
  query: z
    .string()
    .describe(
      'The query for what to reorder from a supplier.'
    ),
});
export type SmartReorderingInput = z.infer<typeof SmartReorderingInputSchema>;

const SmartReorderingOutputSchema = z.object({
  reorderList: z.array(z.string()).describe('A list of items to reorder.'),
});
export type SmartReorderingOutput = z.infer<typeof SmartReorderingOutputSchema>;

export async function smartReordering(input: SmartReorderingInput): Promise<SmartReorderingOutput> {
  return smartReorderingFlow(input);
}

const prompt = ai.definePrompt({
  name: 'smartReorderingPrompt',
  input: {schema: SmartReorderingInputSchema},
  output: {schema: SmartReorderingOutputSchema},
  prompt: `You are an expert inventory manager specializing in advising users what to reorder from which supplier.

You will take the user's query and respond with a list of items to reorder.

Query: {{{query}}}`,
});

const smartReorderingFlow = ai.defineFlow(
  {
    name: 'smartReorderingFlow',
    inputSchema: SmartReorderingInputSchema,
    outputSchema: SmartReorderingOutputSchema,
  },
  async input => {
    const {output} = await prompt(input);
    return output!;
  }
);
