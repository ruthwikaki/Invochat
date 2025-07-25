
'use server';
/**
 * @fileOverview Defines a Genkit tool for calculating inventory turnover rate.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getInventoryTurnoverFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';

const InventoryTurnoverReportSchema = z.object({
    turnover_rate: z.number().describe("The number of times inventory is sold and replaced over the period."),
    total_cogs: z.number().nonnegative().describe("The total cost of goods sold during the period."),
    average_inventory_value: z.number().nonnegative().describe("The average value of the inventory during the period."),
    period_days: z.number().int().describe("The number of days in the analysis period.")
});

const MAX_DAYS_LOOKBACK = 730; // 2 years

export const getInventoryTurnoverReport = ai.defineTool(
  {
    name: 'getInventoryTurnoverReport',
    description:
      "Calculates the inventory turnover rate for a given period (max 730 days). Use this when the user asks about 'inventory turnover', 'how fast inventory is selling', or 'stock turn'. This report shows how many times a company has sold and replaced its inventory over a given period.",
    inputSchema: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
      days: z.number().int().positive().default(90).describe("The number of days to look back for the calculation period."),
    }),
    outputSchema: InventoryTurnoverReportSchema,
  },
  async (input) => {
    logger.info(`[Inventory Turnover Tool] Getting report for company: ${input.companyId}`);
    try {
        const safeDays = Math.min(input.days, MAX_DAYS_LOOKBACK);
        const result = await getInventoryTurnoverFromDB(input.companyId, safeDays);

        // Prevent division by zero errors
        if (result.average_inventory_value === 0) {
            return {
                ...result,
                turnover_rate: 0, // Set turnover to 0 if there's no inventory value
            };
        }
        
        return InventoryTurnoverReportSchema.parse(result);

    } catch (e) {
        logError(e, { context: `[Inventory Turnover Tool] Failed to run RPC for company ${input.companyId}` });
        throw new Error('An error occurred while trying to calculate the inventory turnover rate.');
    }
  }
);
