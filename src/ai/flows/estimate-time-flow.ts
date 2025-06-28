'use server';
/**
 * @fileOverview A lightweight flow to estimate query response time.
 * - getEstimatedTimeForQuery - A function that estimates query complexity.
 */

import {ai} from '@/ai/genkit';
import {z} from 'zod';
import { APP_CONFIG } from '@/config/app-config';

const TimeEstimateOutputSchema = z.enum(['short', 'medium', 'long']);
export type TimeEstimateOutput = z.infer<typeof TimeEstimateOutputSchema>;

export async function getEstimatedTimeForQuery(query: string): Promise<TimeEstimateOutput> {
  return estimateTimeFlow(query);
}

const estimationPrompt = ai.definePrompt({
  name: 'queryTimeEstimator',
  input: {schema: z.string()},
  output: {schema: TimeEstimateOutputSchema},
  prompt: `
    You are a query complexity analyzer. Your job is to predict how long a user's request will take to process based on its complexity.
    The user's request is: "{{input}}"

    Analyze the request and classify it into one of three categories:
    - 'short': For simple lookups, greetings, or direct questions. (e.g., "how many items are in stock?", "what is the value of SKU 123?")
    - 'medium': For requests involving simple aggregations or filtering. (e.g., "show me sales this month", "list all suppliers in California")
    - 'long': For complex analysis, comparisons, multi-step calculations, or open-ended questions. (e.g., "compare this month's sales to last month", "find suspicious patterns", "which products should I discount?")

    Respond with ONLY one of the three category strings: 'short', 'medium', or 'long'. Do not add any other text.
  `,
});

const estimateTimeFlow = ai.defineFlow(
  {
    name: 'estimateTimeFlow',
    inputSchema: z.string(),
    outputSchema: TimeEstimateOutputSchema,
  },
  async (query) => {
    const {output} = await estimationPrompt(query, {model: APP_CONFIG.ai.model});
    return output || 'medium'; // Default to medium if the model fails
  }
);
