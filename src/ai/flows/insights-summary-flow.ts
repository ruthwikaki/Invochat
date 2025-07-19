
'use server';
/**
 * @fileOverview A Genkit flow to generate a concise business summary based on key metrics.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { AnomalySchema } from '@/types';
import { config } from '@/config/app-config';

const InsightsInputSchema = z.object({
  anomalies: z.array(AnomalySchema).describe("A list of recent business anomalies (e.g., unusual spikes in revenue or customer count)."),
  lowStockCount: z.number().int().describe("The number of items currently low on stock."),
  deadStockCount: z.number().int().describe("The number of items considered dead stock (unsold for a long time)."),
});
export type InsightsInput = z.infer<typeof InsightsInputSchema>;

const InsightsOutputSchema = z.object({
  summary: z.string().describe("A concise, natural-language paragraph summarizing the most important business insights. Should be friendly and direct."),
});
export type InsightsOutput = z.infer<typeof InsightsOutputSchema>;


const insightsSummaryPrompt = ai.definePrompt({
  name: 'insightsSummaryPrompt',
  input: { schema: InsightsInputSchema },
  output: { schema: InsightsOutputSchema },
  prompt: `
    You are an expert business analyst AI for an e-commerce company. Your task is to provide a brief, high-level summary of the company's current status based on the provided data points.

    Here is the data:
    - Recent Anomalies: {{{json anomalies}}}
    - Number of Low Stock Items: {{{lowStockCount}}}
    - Number of Dead Stock Items: {{{deadStockCount}}}

    Synthesize this information into a single, easy-to-read paragraph.
    - Start with the most significant piece of information.
    - If there are anomalies, mention them.
    - Mention the number of low stock and dead stock items if they are greater than zero, as this indicates areas for action.
    - Keep it concise and professional, but with a slightly friendly and helpful tone.
    - If all counts are zero and there are no anomalies, provide a positive, reassuring message.

    Example for positive scenario: "Things are looking stable right now. There have been no major anomalies in your sales data, and your inventory levels are healthy with no low stock or dead stock items to report. Keep up the great work!"
    Example for negative scenario: "Your sales data shows a recent anomaly in revenue, which is worth investigating. You currently have {{lowStockCount}} items running low on stock that may need reordering, and {{deadStockCount}} dead stock items are tying up capital."
  `,
});

export async function generateInsightsSummary(input: InsightsInput): Promise<string> {
    const { output } = await insightsSummaryPrompt(input, { model: config.ai.model });
    return output?.summary || "Could not generate a summary at this time.";
}
