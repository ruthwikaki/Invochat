
'use server';
/**
 * @fileOverview Defines a Genkit tool for analyzing supplier performance.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getSupplierPerformanceFromDB } from '@/services/database';
import type { SupplierPerformanceReport } from '@/types';
import { SupplierPerformanceReportSchema } from '@/types';
import { logError } from '@/lib/error-handler';

export const getSupplierPerformanceReport = ai.defineTool(
  {
    name: 'getSupplierPerformanceReport',
    description:
      "Use this tool to get a supplier performance report. This report analyzes historical purchase order data to determine which suppliers deliver on time. Use it when the user asks about 'supplier performance', 'which vendor is best', 'on-time delivery', or 'supplier reliability'.",
    input: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
    }),
    output: z.array(SupplierPerformanceReportSchema),
  },
  async (input): Promise<SupplierPerformanceReport[]> => {
    logger.info(`[Supplier Performance Tool] Getting report for company: ${input.companyId}`);
    try {
        const performanceData = await getSupplierPerformanceFromDB(input.companyId);
        logger.info(`[Supplier Performance Tool] Found data for ${performanceData.length} suppliers.`);
        return performanceData;
    } catch (e) {
        logError(e, { context: `[Supplier Performance Tool] Failed to generate report for company ${input.companyId}` });
        throw new Error('An error occurred while trying to generate the supplier performance report.');
    }
  }
);
