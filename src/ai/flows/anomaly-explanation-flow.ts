
'use server';
/**
 * @fileOverview A Genkit flow to generate explanations for data anomalies.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import type { AnomalyExplanationInput, AnomalyExplanationOutput } from '@/types';
import { AnomalyExplanationInputSchema, AnomalyExplanationOutputSchema } from '@/types';


const anomalyExplanationPrompt = ai.definePrompt({
  name: 'anomalyExplanationPrompt',
  input: { schema: AnomalyExplanationInputSchema },
  output: { schema: AnomalyExplanationOutputSchema },
  prompt: `
    You are a business intelligence analyst. Your task is to explain a data anomaly detected in an e-commerce business's data.

    **Anomaly Data:**
    - Date: {{{anomaly.date}}}
    - Metric: {{{anomaly.anomaly_type}}}
    - Actual Value: {{{anomaly.daily_revenue}}}
    - Expected Value (30-day avg): {{{anomaly.avg_revenue}}}
    - Deviation: {{{anomaly.deviation_percentage}}}%

    **Date Context:**
    - Day of Week: {{{dateContext.dayOfWeek}}}
    - Month: {{{dateContext.month}}}
    - Season: {{{dateContext.season}}}
    {{#if dateContext.knownHoliday}}
    - Holiday Context: This day was near or on {{{dateContext.knownHoliday}}}.
    {{/if}}

    **Your Task:**
    1.  **Analyze:** Based on the anomaly and the context, determine the most likely cause. Consider common business cycles (e.g., weekend sales dips, end-of-month pushes) and holiday impacts.
    2.  **Explain:** Write a concise, 1-2 sentence explanation.
        - Example (Revenue Spike): "The 75% revenue spike on Dec 23rd was likely driven by last-minute holiday shopping."
        - Example (Revenue Dip): "The revenue dip on Monday is typical after a weekend sales push."
    3.  **Confidence:** Rate your confidence as 'high', 'medium', or 'low'. High confidence is for clear, obvious causes (e.g., Black Friday). Medium is for likely causes (e.g., start of summer). Low is for when you are mostly guessing.
    4.  **Suggest Action:** If relevant, provide a brief, actionable suggestion.
        - Example (Holiday Spike): "Consider increasing ad spend and inventory for next year's holiday season."
        - Example (Inventory Drop): "Review stock levels for best-sellers to prepare for replenishment."

    Provide your response in the format specified by the output schema.
  `,
});


export async function generateAnomalyExplanation(input: AnomalyExplanationInput): Promise<AnomalyExplanationOutput> {
    const { output } = await anomalyExplanationPrompt(input);
    if (!output) {
        return {
            explanation: "Could not determine a cause for this anomaly.",
            confidence: 'low',
            suggestedAction: "Manually review sales and inventory data for this date."
        };
    }
    return output;
}
