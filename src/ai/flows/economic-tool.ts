
'use server';
/**
 * @fileOverview Defines a Genkit tool for fetching real-time economic indicators.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { logError } from '@/lib/error-handler';
import { config } from '@/config/app-config';

const EconomicIndicatorInputSchema = z.object({
  indicator: z
    .string()
    .describe(
      'The specific economic indicator to look up (e.g., "US inflation rate", "federal funds rate").'
    ),
});

const EconomicIndicatorOutputSchema = z.object({
    indicator: z.string(),
    value: z.string(),
});

const economicIndicatorPrompt = ai.definePrompt({
  name: 'economicIndicatorPrompt',
  input: { schema: EconomicIndicatorInputSchema },
  prompt: `You are a financial data assistant. Provide a concise, factual answer for the following economic indicator: "{{indicator}}". State only the value and the period it applies to. Example: "3.3% (May 2024)"`,
  config: {
    temperature: 0,
    maxOutputTokens: 100,
    safetySettings: [
        { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_ONLY_HIGH' },
        { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_ONLY_HIGH' },
        { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_ONLY_HIGH' },
        { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_ONLY_HIGH' },
    ]
  }
});


export const getEconomicIndicators = ai.defineTool(
  {
    name: 'getEconomicIndicators',
    description:
      "Use to get current values for major economic indicators like inflation rate (CPI), federal funds rate, unemployment rate, or GDP growth rate. Use this tool ONLY when the user's question is primarily about a specific, well-known economic metric and CANNOT be answered from the database.",
    inputSchema: EconomicIndicatorInputSchema,
    outputSchema: EconomicIndicatorOutputSchema,
  },
  async (input) => {
    logger.info(`[Economic Tool] Looking up indicator: ${input.indicator}`);
    try {
        const { output } = await economicIndicatorPrompt({ indicator: input.indicator }, { model: config.ai.model });
        
        return {
            indicator: input.indicator,
            value: output?.text || "Could not retrieve value."
        };

    } catch (e) {
        logError(e, { context: `[Economic Tool] Failed to get data for ${input.indicator}` });
        throw new Error('Could not retrieve information for the requested economic indicator.');
    }
  }
);
