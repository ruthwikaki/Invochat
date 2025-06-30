
'use server';
/**
 * @fileOverview Defines a Genkit tool for getting a dead stock report.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getDeadStockPageData } from '@/services/database';
import { DeadStockItemSchema } from '@/types';

export const getDeadStockReport = ai.defineTool(
  {
    name: 'getDeadStockReport',
    description:
      "Use this tool to get a report of dead stock items. Dead stock are items that haven't sold in a long time (e.g., over 90 days). Use this when the user asks about 'dead stock', 'unsold items', 'stale inventory', or 'slow-moving products'.",
    input: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
    }),
    output: z.array(DeadStockItemSchema),
  },
  async (input): Promise<any[]> => {
    logger.info(`[Dead Stock Tool] Getting report for company: ${input.companyId}`);
    try {
        const deadStockData = await getDeadStockPageData(input.companyId);
        // The tool should return just the items, not the totals.
        return deadStockData.deadStockItems;
    } catch (e) {
        logger.error(`[Dead Stock Tool] Failed to generate report for company ${input.companyId}`, e);
        return [];
    }
  }
);
