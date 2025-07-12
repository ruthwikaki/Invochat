
'use server';
/**
 * @fileOverview A Genkit flow to generate explanations for business alerts.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import type { Alert } from '@/types';
import { AlertSchema } from '@/types';

const AlertExplanationInputSchema = z.object({
  alert: AlertSchema,
});

const AlertExplanationOutputSchema = z.object({
  explanation: z.string().describe("A concise, 1-2 sentence explanation for the root cause of the alert."),
  suggestedAction: z.string().describe("A brief, actionable suggestion for the user to resolve the alert."),
});

const alertExplanationPrompt = ai.definePrompt({
  name: 'alertExplanationPrompt',
  input: { schema: AlertExplanationInputSchema },
  output: { schema: AlertExplanationOutputSchema },
  prompt: `
    You are a business intelligence analyst. Your task is to explain a business alert and suggest a next step.

    **Alert Data:**
    - Type: {{{alert.type}}}
    - Title: {{{alert.title}}}
    - Message: {{{alert.message}}}
    - Severity: {{{alert.severity}}}
    - Metadata: {{{json alert.metadata}}}

    **Your Task:**
    1.  **Analyze:** Based on the alert type and its metadata, determine the most likely root cause.
    2.  **Explain:** Write a concise, 1-2 sentence explanation.
        - Example (Low Stock): "This item's sales have accelerated recently, and the current stock is below the reorder point."
        - Example (Profit Warning): "The profit margin for this product has decreased, likely due to a recent increase in supplier cost."
    3.  **Suggest Action:** Provide a brief, actionable suggestion.
        - Example (Low Stock): "Consider creating a purchase order from its primary supplier."
        - Example (Dead Stock): "Suggest creating a promotional campaign to liquidate this inventory."

    Provide your response in the specified JSON format.
  `,
});

export async function generateAlertExplanation(alert: Alert) {
  const { output } = await alertExplanationPrompt({ alert });
  if (!output) {
    return {
      explanation: "Could not determine a cause for this alert.",
      suggestedAction: "Manually review sales and inventory data related to this alert.",
    };
  }
  return output;
}
