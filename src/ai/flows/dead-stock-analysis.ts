'use server';

/**
 * @fileOverview A flow for analyzing dead stock and identifying slow-moving inventory.
 */

import {ai} from '@/ai/genkit';
import { getDeadStockFromDB } from '@/services/database';
import {z} from 'genkit';

// Define the input schema.
const AnalyzeDeadStockInputSchema = z.object({
  query: z
    .string()
    .describe('The user query related to dead stock analysis.'),
});
export type AnalyzeDeadStockInput = z.infer<typeof AnalyzeDeadStockInputSchema>;

// Define the output schema.
const AnalyzeDeadStockOutputSchema = z.object({
  deadStockItems: z.array(
    z.object({
      item: z.string().describe('The name or identifier of the item.'),
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
    inputSchema: z.object({}),
    outputSchema: z.array(z.any()),
}, async () => {
    const items = await getDeadStockFromDB();
    return items.map(item => ({
        item: item.name,
        quantity: item.quantity,
        lastSold: item.last_sold_date,
        reason: 'Not sold in 90+ days'
    }));
});

// Define the prompt.
const deadStockPrompt = ai.definePrompt({
  name: 'deadStockPrompt',
  tools: [getDeadStockTool],
  prompt: `A user is asking about dead stock. Use the getDeadStockData tool to retrieve the information and return it. The schema will be automatically handled.`,
});

// Define the Genkit flow.
const analyzeDeadStockFlow = ai.defineFlow(
  {
    name: 'analyzeDeadStockFlow',
    inputSchema: AnalyzeDeadStockInputSchema,
    outputSchema: AnalyzeDeadStockOutputSchema,
  },
  async () => {
    const response = await deadStockPrompt({});
    const toolResponse = response.toolRequest('getDeadStockData');
    if (!toolResponse) {
        throw new Error("Failed to get dead stock data from tool.");
    }

    return { deadStockItems: toolResponse.output as any[] };
  }
);


// Exported function to initiate the dead stock analysis flow.
export async function analyzeDeadStock(input: AnalyzeDeadStockInput): Promise<AnalyzeDeadStockOutput> {
  return analyzeDeadStockFlow(input);
}
