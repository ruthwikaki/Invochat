
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

// A generic schema for tools that only require a companyId
const CompanyIdInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to get the report for."),
});

export const getDemandForecast = ai.defineTool(
  {
    name: 'getDemandForecast',
    description: "Use to forecast product demand for the next 30 days based on the last 12 months of sales data. This is useful for predicting future sales and planning inventory levels.",
    input: CompanyIdInputSchema,
    output: z.any(),
  },
  async ({ companyId }) => {
    logger.info(`[Analytics Tool] Getting demand forecast for company: ${companyId}`);
    return db.getDemandForecastFromDB(companyId);
  }
);

export const getAbcAnalysis = ai.defineTool(
  {
    name: 'getAbcAnalysis',
    description: "Performs an ABC analysis on the inventory. This categorizes products into A, B, and C tiers based on their revenue contribution (A being the most valuable). Use this to prioritize inventory management efforts.",
    input: CompanyIdInputSchema,
    output: z.any(),
  },
  async ({ companyId }) => {
    logger.info(`[Analytics Tool] Performing ABC analysis for company: ${companyId}`);
    return db.getAbcAnalysisFromDB(companyId);
  }
);

export const getGrossMarginAnalysis = ai.defineTool(
  {
    name: 'getGrossMarginAnalysis',
    description: "Analyzes gross profit margins by product and sales channel over the last 90 days. Useful for understanding which products and channels are most profitable.",
    input: CompanyIdInputSchema,
    output: z.any(),
  },
  async ({ companyId }) => {
    logger.info(`[Analytics Tool] Getting gross margin analysis for company: ${companyId}`);
    return db.getGrossMarginAnalysisFromDB(companyId);
  }
);

export const getNetMarginByChannel = ai.defineTool(
  {
    name: 'getNetMarginByChannel',
    description: "Calculates the net margin for a specific sales channel, taking into account configured channel fees. Use this for a precise profitability analysis of a single channel like 'Shopify' or 'Amazon'.",
    input: z.object({
      companyId: z.string().uuid(),
      channelName: z.string().describe("The specific sales channel to analyze (e.g., 'Shopify'). This MUST match a name in the 'channel_fees' table."),
    }),
    output: z.any(),
  },
  async ({ companyId, channelName }) => {
    logger.info(`[Analytics Tool] Getting net margin for channel '${channelName}' for company: ${companyId}`);
    return db.getNetMarginByChannelFromDB(companyId, channelName);
  }
);

export const getMarginTrends = ai.defineTool(
  {
    name: 'getMarginTrends',
    description: "Shows the trend of gross profit margin over the last 12 months, aggregated monthly. Helps identify seasonality or changes in overall profitability over time.",
    input: CompanyIdInputSchema,
    output: z.any(),
  },
  async ({ companyId }) => {
    logger.info(`[Analytics Tool] Getting margin trends for company: ${companyId}`);
    return db.getMarginTrendsFromDB(companyId);
  }
);
