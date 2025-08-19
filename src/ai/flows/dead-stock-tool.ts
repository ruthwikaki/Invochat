
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting a dead stock report.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getDeadStockReportFromDB } from '@/services/database';
import { DeadStockItemSchema } from '@/types';
import { logError } from '@/lib/error-handler';

const DeadStockReportSchema = z.object({
  deadStockItems: z.array(DeadStockItemSchema),
  totalValue: z.number(),
  totalUnits: z.number(),
});

export const getDeadStockReport = ai.defineTool(
  {
    name: 'getDeadStockReport',
    description:
      "Use this tool to get a report of dead stock items. Dead stock are items that haven't sold in a long time. The definition of 'a long time' is based on the company's settings (default 90 days). Use this when the user asks about 'dead stock', 'unsold items', 'stale inventory', or 'slow-moving products'.",
    inputSchema: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
    }),
    outputSchema: DeadStockReportSchema,
  },
  async (input): Promise<z.infer<typeof DeadStockReportSchema>> => {
    logger.info(`[Dead Stock Tool] Getting report for company: ${input.companyId}`);
    try {
        const deadStockData = await getDeadStockReportFromDB(input.companyId);
        
        if (deadStockData.deadStockItems.length === 0) {
            logger.info(`[Dead Stock Tool] No dead stock found for company ${input.companyId}`);
        }
        
        return deadStockData;
    } catch (e) {
        logError(e, { context: `[Dead Stock Tool] Failed to generate report for company ${input.companyId}` });
        throw new Error('An error occurred while trying to generate the dead stock report.');
    }
  }
);
