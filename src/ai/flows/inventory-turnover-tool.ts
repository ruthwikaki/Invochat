'use server';
/**
 * @fileOverview Defines a Genkit tool for calculating inventory turnover rate.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';

const InventoryTurnoverReportSchema = z.object({
    turnover_rate: z.number().describe("The number of times inventory is sold and replaced over the period."),
    total_cogs: z.number().describe("The total cost of goods sold during the period."),
    average_inventory_value: z.number().describe("The average value of the inventory during the period. For this calculation, it's based on the current total inventory value."),
    period_days: z.number().int().describe("The number of days in the analysis period.")
});

export const getInventoryTurnoverReport = ai.defineTool(
  {
    name: 'getInventoryTurnoverReport',
    description:
      "Calculates the inventory turnover rate. Use this when the user asks about 'inventory turnover', 'how fast inventory is selling', or 'stock turn'. This report shows how many times a company has sold and replaced its inventory over a given period.",
    input: z.object({
      companyId: z.string().uuid().describe("The ID of the company to get the report for."),
      days: z.number().int().positive().default(90).describe("The number of days to look back for the calculation period."),
    }),
    output: InventoryTurnoverReportSchema,
  },
  async (input) => {
    logger.info(`[Inventory Turnover Tool] Getting report for company: ${input.companyId}`);
    const supabase = getServiceRoleClient();

    const query = `
      WITH cogs_calc AS (
          SELECT SUM(oi.quantity * COALESCE(i.landed_cost, i.cost)) as total_cogs
          FROM order_items oi
          JOIN orders o ON oi.sale_id = o.id
          JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
          WHERE o.company_id = '${input.companyId}'
            AND o.sale_date >= CURRENT_DATE - INTERVAL '${input.days} days'
      ),
      inventory_value AS (
          SELECT SUM(quantity * COALESCE(landed_cost, cost)) as total_inventory_value
          FROM inventory
          WHERE company_id = '${input.companyId}'
      )
      SELECT
          COALESCE(c.total_cogs, 0) as total_cogs,
          COALESCE(iv.total_inventory_value, 0) as total_inventory_value,
          CASE
              WHEN iv.total_inventory_value > 0 THEN COALESCE(c.total_cogs, 0) / iv.total_inventory_value
              ELSE 0
          END as turnover_rate
      FROM cogs_calc c, inventory_value iv;
    `;
    
    const { data, error } = await supabase.rpc('execute_dynamic_query', {
        query_text: query.trim().replace(/;/g, '')
    });
    
    if (error) {
        logError(error, { context: `[Inventory Turnover Tool] Failed to run query for company ${input.companyId}` });
        throw new Error('Failed to calculate inventory turnover.');
    }

    const result = data[0];

    return {
        turnover_rate: Number(result.turnover_rate || 0),
        total_cogs: Number(result.total_cogs || 0),
        average_inventory_value: Number(result.total_inventory_value || 0),
        period_days: input.days,
    };
  }
);
