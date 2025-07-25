
'use server';
/**
 * @fileOverview A Genkit flow to generate insights from customer segment data.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import type { CustomerSegmentAnalysisItem } from '@/types';
import { config } from '@/config/app-config';

const CustomerInsightsInputSchema = z.object({
  segments: z.array(z.custom<CustomerSegmentAnalysisItem>()),
});

const CustomerInsightsOutputSchema = z.object({
  analysis: z.string().describe("A concise, 1-2 sentence summary of the most interesting finding from the customer segment data."),
  suggestion: z.string().describe("An actionable marketing or sales suggestion based on the analysis."),
});

export const customerInsightsPrompt = ai.definePrompt({
  name: 'customerInsightsPrompt',
  input: { schema: CustomerInsightsInputSchema },
  output: { schema: CustomerInsightsOutputSchema },
  prompt: `
    You are a marketing strategist for an e-commerce business. Analyze the following customer segment data, which shows which products are popular with different customer groups.

    **Customer Segment Data:**
    {{{json segments}}}

    **Your Task:**
    1.  **Analyze:** Review the data to find the most interesting or actionable insight. Look for patterns. Do new customers overwhelmingly prefer a specific product? Do top spenders buy a particular high-margin item?
    2.  **Summarize Analysis:** Write a 1-2 sentence summary of your key finding.
        - Example: "Your 'Super Widget' is the most popular product for acquiring new customers, while repeat customers tend to purchase 'Premium Filters'."
    3.  **Provide Suggestion:** Based on your analysis, provide a concrete, actionable marketing suggestion.
        - Example: "Consider creating a targeted ad campaign for the 'Super Widget' aimed at new audiences, and offer a small discount on 'Premium Filters' to your existing customer base to encourage repeat business."

    Provide your response in the specified JSON format.
  `,
});

export const getCustomerInsights = ai.defineTool({
    name: 'getCustomerInsights',
    description: "Analyzes customer segment data to provide a summary and actionable marketing suggestion.",
    inputSchema: CustomerInsightsInputSchema,
    outputSchema: CustomerInsightsOutputSchema,
}, async (input) => {
    const { output } = await customerInsightsPrompt(input, { model: config.ai.model });
    if (!output) {
        throw new Error("AI failed to generate customer insights.");
    }
    return output;
});
