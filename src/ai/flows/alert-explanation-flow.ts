
'use server';
/**
 * @fileOverview A Genkit flow to generate explanations for business alerts.
 */

import { ai } from '@/ai/genkit';
import type { AnomalyExplanationInput, AnomalyExplanationOutput } from '@/types';
import { AnomalyExplanationInputSchema, AnomalyExplanationOutputSchema } from '@/types';
import { config } from '@/config/app-config';

const alertExplanationPrompt = ai.definePrompt({
  name: 'alertExplanationPrompt',
  input: { schema: AnomalyExplanationInputSchema },
  output: { schema: AnomalyExplanationOutputSchema },
  prompt: `
    You are a business intelligence analyst. Your task is to explain a business alert and suggest a next step.

    **Alert Data:**
    - Type: {{{type}}}
    - Title: {{{title}}}
    - Message: {{{message}}}
    - Severity: {{{severity}}}
    - Metadata: {{{json metadata}}}

    **Your Task:**
    1.  **Analyze:** Based on the alert type and its metadata, determine the most likely root cause.
    2.  **Explain:** Write a concise, 1-2 sentence explanation.
        - Example (Low Stock): "This item's sales have accelerated recently, and the current stock is below the reorder point."
        - Example (Profit Warning): "The profit margin for this product has decreased, likely due to a recent increase in supplier cost."
    3.  **Suggest Action:** Provide a brief, actionable suggestion.
        - Example (Low Stock): "Consider creating a purchase order from its primary supplier."
        - Example (Dead Stock): "Suggest creating a promotional campaign to liquidate this inventory."
    4. **Confidence:** Rate your confidence in the explanation as 'high', 'medium', or 'low'.

    Provide your response in the specified JSON format.
  `,
});

export async function generateAlertExplanation(alert: AnomalyExplanationInput): Promise<AnomalyExplanationOutput> {
  const { output } = await alertExplanationPrompt(alert, { model: config.ai.model });
  if (!output) {
    return {
      explanation: "Could not determine a cause for this alert.",
      suggestedAction: "Manually review sales and inventory data related to this alert.",
      confidence: 'low',
    };
  }
  return output;
}
