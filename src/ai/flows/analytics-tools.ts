
'use server';
/**
 * @fileOverview Defines a suite of Genkit tools for performing secure, advanced analytics.
 * These tools call pre-defined, parameterized SQL functions in the database, eliminating
 * the risk of AI-generated SQL injection.
 */
import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { logger } from '@/lib/logger';
import * as db from '@/services/database';
import { getErrorMessage, logError } from '@/lib/error-handler';

// A generic schema for tools that only require a companyId
const CompanyIdInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to get the report for."),
});

export const getSalesVelocity = ai.defineTool(
    {
        name: 'getSalesVelocity',
        description: "Identifies the fastest and slowest-selling products over a specified period (default 90 days) based on total units sold. Use this for 'best sellers', 'worst sellers', 'fast movers', or 'slow movers' queries.",
        inputSchema: z.object({
            companyId: z.string().uuid(),
            days: z.number().int().positive().default(90),
            limit: z.number().int().positive().default(10),
        }),
        outputSchema: z.any(),
    },
    async ({ companyId, days, limit }) => {
        try {
            logger.info(`[Analytics Tool] Getting sales velocity for company: ${companyId}`);
            return await db.getSalesVelocityFromDB(companyId, days, limit);
        } catch (e) {
            logError(e, { context: `[Analytics Tool] Sales velocity failed for company ${companyId}` });
            throw new Error('An error occurred while trying to generate the sales velocity report.');
        }
    }
);

export const getDemandForecast = ai.defineTool(
  {
    name: 'getDemandForecast',
    description: "Use to forecast product demand for the next 30 days based on the last 12 months of sales data. This is useful for predicting future sales and planning inventory levels.",
    inputSchema: CompanyIdInputSchema,
    outputSchema: z.any(),
  },
  async ({ companyId }) => {
    try {
        logger.info(`[Analytics Tool] Getting demand forecast for company: ${companyId}`);
        return await db.getDemandForecastFromDB(companyId);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Demand forecast failed for company ${companyId}`});
        throw new Error('An error occurred while trying to generate the demand forecast.');
    }
  }
);

export const getAbcAnalysis = ai.defineTool(
  {
    name: 'getAbcAnalysis',
    description: "Performs an ABC analysis on the inventory. This categorizes products into A, B, and C tiers based on their revenue contribution (A being the most valuable). Use this to prioritize inventory management efforts.",
    inputSchema: CompanyIdInputSchema,
    outputSchema: z.any(),
  },
  async ({ companyId }) => {
    try {
        logger.info(`[Analytics Tool] Performing ABC analysis for company: ${companyId}`);
        return await db.getAbcAnalysisFromDB(companyId);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] ABC analysis failed for company ${companyId}`});
        throw new Error('An error occurred while trying to perform the ABC analysis.');
    }
  }
);

export const getGrossMarginAnalysis = ai.defineTool(
  {
    name: 'getGrossMarginAnalysis',
    description: "Analyzes gross profit margins by product and sales channel over the last 90 days. Useful for understanding which products and channels are most profitable.",
    inputSchema: CompanyIdInputSchema,
    outputSchema: z.any(),
  },
  async ({ companyId }) => {
    try {
        logger.info(`[Analytics Tool] Getting gross margin analysis for company: ${companyId}`);
        return await db.getGrossMarginAnalysisFromDB(companyId);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Gross margin analysis failed for company ${companyId}`});
        throw new Error('An error occurred while trying to generate the gross margin analysis.');
    }
  }
);

export const getNetMarginByChannel = ai.defineTool(
  {
    name: 'getNetMarginByChannel',
    description: "Calculates the net margin for a specific sales channel, taking into account configured channel fees. Use this for a precise profitability analysis of a single channel like 'Shopify' or 'Amazon'.",
    inputSchema: z.object({
      companyId: z.string().uuid(),
      channelName: z.string().describe("The specific sales channel to analyze (e.g., 'Shopify'). This MUST match a name in the 'channel_fees' table."),
    }),
    outputSchema: z.any(),
  },
  async ({ companyId, channelName }) => {
    try {
        logger.info(`[Analytics Tool] Getting net margin for channel '${channelName}' for company: ${companyId}`);
        return await db.getNetMarginByChannelFromDB(companyId, channelName);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Net margin analysis for channel '${channelName}' failed for company ${companyId}`});
        throw new Error(`An error occurred while trying to generate the net margin analysis for ${channelName}.`);
    }
  }
);

export const getMarginTrends = ai.defineTool(
  {
    name: 'getMarginTrends',
    description: "Shows the trend of gross profit margin over the last 12 months, aggregated monthly. Helps identify seasonality or changes in overall profitability over time.",
    inputSchema: CompanyIdInputSchema,
    outputSchema: z.any(),
  },
  async ({ companyId }) => {
    try {
        logger.info(`[Analytics Tool] Getting margin trends for company: ${companyId}`);
        return await db.getMarginTrendsFromDB(companyId);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Margin trends analysis failed for company ${companyId}`});
        throw new Error('An error occurred while trying to generate the margin trend analysis.');
    }
  }
);

export const getFinancialImpactAnalysis = ai.defineTool(
  {
      name: 'getFinancialImpactAnalysis',
      description: "Use for 'what-if' scenarios related to purchasing. Analyzes the financial impact of a potential purchase order without actually creating it. Calculates the cost and its effect on key business metrics.",
      inputSchema: z.object({
        companyId: z.string().uuid(),
        items: z.array(z.object({
            sku: z.string(),
            quantity: z.number().int().positive(),
        })).describe("An array of items (SKU and quantity) to analyze for a potential purchase.")
      }),
      outputSchema: z.any(),
  },
  async ({ companyId, items }) => {
    try {
        logger.info(`[Analytics Tool] Running financial impact analysis for company: ${companyId}`);
        return await db.getFinancialImpactOfPoFromDB(companyId, items);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Financial impact analysis failed for company ${companyId}`});
        throw new Error('An error occurred while trying to run the financial impact analysis.');
    }
  }
);


export const getPromotionalImpactAnalysis = ai.defineTool(
  {
      name: 'getPromotionalImpactAnalysis',
      description: "Use for 'what-if' scenarios related to sales promotions. Analyzes the financial impact of a potential discount or sale. Calculates the estimated impact on sales volume, revenue, and profit.",
      inputSchema: z.object({
        companyId: z.string().uuid(),
        skus: z.array(z.string()).describe("An array of product SKUs to include in the promotion."),
        discountPercentage: z.number().min(0.01).max(0.99).describe("The promotional discount as a decimal (e.g., 0.2 for 20%)."),
        durationDays: z.number().int().positive().describe("The number of days the promotion will run."),
      }),
      outputSchema: z.any(),
  },
  async ({ companyId, skus, discountPercentage, durationDays }) => {
    try {
        logger.info(`[Analytics Tool] Running promotional impact analysis for company: ${companyId}`);
        return await db.getFinancialImpactOfPromotionFromDB(companyId, skus, discountPercentage, durationDays);
    } catch (e) {
        logError(e, { context: `[Analytics Tool] Promotional impact analysis failed for company ${companyId}`});
        throw new Error('An error occurred while trying to run the promotional impact analysis.');
    }
  }
);
