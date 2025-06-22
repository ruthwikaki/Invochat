'use server';

/**
 * @fileOverview A flow for analyzing dead stock and identifying slow-moving inventory.
 *
 * - analyzeDeadStock - A function that initiates the dead stock analysis process.
 * - AnalyzeDeadStockInput - The input type for the analyzeDeadStock function.
 * - AnalyzeDeadStockOutput - The return type for the analyzeDeadStock function, listing items identified as dead stock.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

// Define the input schema for the dead stock analysis.
const AnalyzeDeadStockInputSchema = z.object({
  query: z
    .string()
    .describe(
      'The user query related to dead stock analysis, e.g., \'What is my dead stock?\''
    ),
});
export type AnalyzeDeadStockInput = z.infer<typeof AnalyzeDeadStockInputSchema>;

// Define the output schema for the dead stock analysis, including a list of dead stock items.
const AnalyzeDeadStockOutputSchema = z.object({
  deadStockItems: z.array(
    z.object({
      item: z.string().describe('The name or identifier of the item.'),
      quantity: z.number().describe('The quantity of the item in stock.'),
      lastSold: z
        .string() // Consider using a date type if appropriate
        .describe('The date the item was last sold.'),
      reason: z
        .string()
        .describe(
          'The reason why the item is considered dead stock, e.g., slow-moving, obsolete.'
        ),
    })
  ).describe('A list of items identified as dead stock.'),
});
export type AnalyzeDeadStockOutput = z.infer<typeof AnalyzeDeadStockOutputSchema>;

// Exported function to initiate the dead stock analysis flow.
export async function analyzeDeadStock(input: AnalyzeDeadStockInput): Promise<AnalyzeDeadStockOutput> {
  return analyzeDeadStockFlow(input);
}

// Define the prompt for the dead stock analysis.
const deadStockPrompt = ai.definePrompt({
  name: 'deadStockPrompt',
  input: {schema: AnalyzeDeadStockInputSchema},
  output: {schema: AnalyzeDeadStockOutputSchema},
  prompt: `You are an inventory management expert. Analyze the user's query to identify dead stock items.

  Based on the query: {{{query}}}

  Return a list of items considered dead stock, including their quantity, last sold date, and the reason they are classified as dead stock.
  Consider items with no sales in the last 6 months as dead stock.
  Items from before that time are not to be considered dead stock.
  Ensure the output matches the AnalyzeDeadStockOutputSchema format.`, // Ensure schema compliance
});

// Define the Genkit flow for dead stock analysis.
const analyzeDeadStockFlow = ai.defineFlow(
  {
    name: 'analyzeDeadStockFlow',
    inputSchema: AnalyzeDeadStockInputSchema,
    outputSchema: AnalyzeDeadStockOutputSchema,
  },
  async input => {
    const {output} = await deadStockPrompt(input);
    return output!;
  }
);

