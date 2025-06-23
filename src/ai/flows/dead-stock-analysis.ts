'use server';

/**
 * @fileOverview A flow for analyzing dead stock and identifying slow-moving inventory.
 */

import {ai} from '@/ai/genkit';
import { getDeadStockFromDB } from '@/services/database';
import {z} from 'genkit';
import { isBefore, parseISO, subDays } from 'date-fns';

// Define the input schema.
const AnalyzeDeadStockInputSchema = z.object({
  query: z
    .string()
    .describe('The user query related to dead stock analysis.'),
  companyId: z.string().describe("The user's company ID."),
});
export type AnalyzeDeadStockInput = z.infer<typeof AnalyzeDeadStockInputSchema>;

// Define the output schema.
const AnalyzeDeadStockOutputSchema = z.object({
  deadStockItems: z.array(
    z.object({
      item: z.string().describe('The name or identifier of the item.'),
      sku: z.string().describe('The SKU of the item.'),
      quantity: z.number().describe('The quantity of the item in stock.'),
      lastSold: z.string().describe('The date the item was last sold.'),
      reason: z.string().describe('The reason why the item is considered dead stock.'),
    })
  ).describe('A list of items identified as dead stock.'),
});
export type AnalyzeDeadStockOutput = z.infer<typeof AnalyzeDeadStockOutputSchema>;

// Tool to fetch dead stock data from our "database".
const getDeadStockTool = ai.defineTool({
    name: 'getDeadStockData',
    description: 'Retrieves a list of all products that have not been sold in over 90 days.',
    inputSchema: z.object({ companyId: z.string() }),
    outputSchema: z.array(z.any()),
}, async ({ companyId }) => {
    const items = await getDeadStockFromDB(companyId);
    const ninetyDaysAgo = subDays(new Date(), 90);

    return items
      .filter(item => item.last_sold_date && isBefore(parseISO(item.last_sold_date), ninetyDaysAgo))
      .map(item => ({
        item: item.name,
        sku: item.sku,
        quantity: item.quantity,
        lastSold: item.last_sold_date,
        reason: 'Not sold in 90+ days'
    }));
});

// Define the prompt.
const deadStockPrompt = ai.definePrompt({
  name: 'deadStockPrompt',
  input: { schema: AnalyzeDeadStockInputSchema },
  output: { schema: AnalyzeDeadStockOutputSchema },
  tools: [getDeadStockTool],
  prompt: `You are an expert inventory analyst. A user is asking about dead stock. Their query is: {{{query}}}. Use the getDeadStockData tool to retrieve the information and then format the result to match the output schema.`,
});

// Define the Genkit flow.
const analyzeDeadStockFlow = ai.defineFlow(
  {
    name: 'analyzeDeadStockFlow',
    inputSchema: AnalyzeDeadStockInputSchema,
    outputSchema: AnalyzeDeadStockOutputSchema,
  },
  async (input) => {
    const { output } = await deadStockPrompt(input);
    if (!output) {
        throw new Error('Could not generate dead stock analysis.');
    }
    return output;
  }
);


// Exported function to initiate the dead stock analysis flow.
export async function analyzeDeadStock(input: AnalyzeDeadStockInput): Promise<AnalyzeDeadStockOutput> {
  return analyzeDeadStockFlow(input);
}
