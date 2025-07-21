
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting a dead stock report.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getDeadStockReportFromDB } from '@/services/database';
import { DeadStockItemSchema, type DeadStockItem } from '@/types';
import { logError } from '@/lib/error-handler';

export const getDeadStockReport = ai.defineTool(
  {
    name: 'getDeadStockReport',
    description:
      "Use this tool to get a report of dead stock items. Dead stock are items that haven't sold in a long time (e.g., over 90 days). Use this when the user asks about 'dead stock', 'unsold items', 'stale inventory', or 'slow-moving products'.",
    inputSchema: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
    }),
    outputSchema: z.array(DeadStockItemSchema),
  },
  async (input): Promise<DeadStockItem[]> => {
    logger.info(`[Dead Stock Tool] Getting report for company: ${input.companyId}`);
    try {
        const deadStockData = await getDeadStockReportFromDB(input.companyId);
        // The tool should return just the items, not the totals.
        return deadStockData.deadStockItems;
    } catch (e) {
        logError(e, { context: `[Dead Stock Tool] Failed to generate report for company ${input.companyId}` });
        throw new Error('An error occurred while trying to generate the dead stock report.');
    }
  }
);

