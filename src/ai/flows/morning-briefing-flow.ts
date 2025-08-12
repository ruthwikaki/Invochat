
'use server';
/**
 * @fileOverview A Genkit flow to generate a "morning briefing" summary for the dashboard.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import type { DashboardMetrics } from '@/types';
import { config } from '@/config/app-config';

const MorningBriefingInputSchema = z.object({
  metrics: z.custom<DashboardMetrics>(),
  companyName: z.string().optional(),
});

const MorningBriefingOutputSchema = z.object({
  greeting: z.string().describe("A friendly greeting, like 'Good morning!'"),
  summary: z.string().describe("A concise, 1-3 sentence summary of the most important business event or status. This is the core of the briefing."),
  cta: z.object({
    text: z.string().describe("The text for a call-to-action button."),
    link: z.string().describe("The URL for the call-to-action button."),
  }).optional(),
});

export const morningBriefingPrompt = ai.definePrompt({
  name: 'morningBriefingPrompt',
  input: { schema: MorningBriefingInputSchema },
  output: { schema: MorningBriefingOutputSchema },
  prompt: `
    You are an AI business analyst providing a "morning briefing" for an e-commerce store owner.
    Your tone should be professional, concise, and proactive.

    **Current Business Metrics:**
    {{{json metrics}}}

    **Your Task:**
    1.  **Identify the Single Most Important Thing:** Look at the metrics. What is the most critical piece of information the owner needs to know right now?
        - Is there a sharp drop or spike in sales?
        - Are there a large number of low stock items, risking stockouts?
        - Is there a significant amount of capital tied up in dead stock?
        - If everything is stable, that's also an important insight.
    2.  **Write the Summary:** Craft a 1-3 sentence summary of this key insight.
        - Example (Low Stock): "Your sales are trending up, but you have {{metrics.inventory_summary.low_stock_value}} items running low on stock. I recommend reviewing your reorder suggestions to avoid stockouts."
        - Example (Dead Stock): "I've noticed that {{metrics.dead_stock_value}} in products haven't sold in a while, tying up capital. Let's create a plan to move this inventory."
        - Example (Stable): "Things are looking stable. Your sales are steady and inventory levels are healthy. Keep up the great work!"
    3.  **Create a Call to Action (CTA):** Based on your summary, what is the most logical next step? Provide text and a relevant link for a button.
        - If the issue is low stock, link to '/analytics/reordering'.
        - If the issue is dead stock, link to '/analytics/dead-stock'.
        - If things are stable, you can link to the '/analytics' page for deeper insights.

    Provide your response in the specified JSON format.
  `,
});

export async function generateMorningBriefing(input: { metrics: DashboardMetrics; companyName?: string }) {
    const { output } = await morningBriefingPrompt(input, { model: config.ai.model });
    if (!output) {
      return {
        greeting: 'Hello!',
        summary: 'Could not generate a business summary at this time. Please check your dashboard for the latest metrics.',
      };
    }
    return output;
}
