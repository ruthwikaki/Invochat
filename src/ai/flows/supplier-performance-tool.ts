
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
        // This is a complex report, so it's okay if it fails. Return empty.
        logger.error(`[Supplier Performance Tool] Failed to generate report for company ${input.companyId}`, e);
        return [];
    }
  }
);
