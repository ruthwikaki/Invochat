
'use server';
/**
 * @fileOverview Defines a Genkit tool for fetching real-time economic indicators.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';

export const getEconomicIndicators = ai.defineTool(
  {
    name: 'getEconomicIndicators',
    description:
      "Use to get current values for major economic indicators like inflation rate (CPI), federal funds rate, unemployment rate, or GDP growth rate. Use this tool ONLY when the user's question is primarily about a specific, well-known economic metric and CANNOT be answered from the database.",
    input: z.object({
      indicator: z
        .string()
        .describe(
          'The specific economic indicator to look up (e.g., "US inflation rate", "federal funds rate").'
        ),
    }),
    output: z.object({
        indicator: z.string(),
        value: z.string(),
    }),
  },
  async (input) => {
    logger.info(`[Economic Tool] Looking up indicator: ${input.indicator}`);
    try {
        const { text } = await ai.generate({
            model: 'googleai/gemini-1.5-flash',
            prompt: `You are a financial data assistant. Provide a concise, factual answer for the following economic indicator: "${input.indicator}". State only the value and the period it applies to. Example: "3.3% (May 2024)"`,
            temperature: 0,
        });
        
        return {
            indicator: input.indicator,
            value: text
        };

    } catch (e: any) {
        logger.error(`[Economic Tool] Failed to get data for ${input.indicator}`, e);
        return {
            indicator: input.indicator,
            value: "Could not retrieve information."
        };
    }
  }
);
