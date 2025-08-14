
'use server';
/**
 * @fileOverview A Genkit flow to forecast future demand for a single product
 * using linear regression on historical sales data.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getHistoricalSalesForSingleSkuFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';
import { linearRegression } from '@/lib/utils';
import { differenceInDays } from 'date-fns';
import { config } from '@/config/app-config';

const ForecastInputSchema = z.object({
  companyId: z.string().uuid(),
  sku: z.string().describe("The SKU of the product to forecast demand for."),
  daysToForecast: z.number().int().positive().default(30),
});

const ForecastOutputSchema = z.object({
  sku: z.string(),
  forecastedDemand: z.number().int().describe("The estimated number of units to be sold in the forecast period."),
  confidence: z.enum(['High', 'Medium', 'Low']).describe("The confidence level in the forecast."),
  analysis: z.string().describe("A concise, natural-language paragraph summarizing the forecast, trend, and reasoning."),
  trend: z.enum(['Upward', 'Downward', 'Stable']).describe("The detected sales trend."),
});

const generateForecastAnalysisPrompt = ai.definePrompt({
  name: 'generateForecastAnalysisPrompt',
  input: { schema: z.object({
    sku: z.string(),
    daysToForecast: z.number(),
    slope: z.number(),
    intercept: z.number(),
    dataPointCount: z.number(),
    forecastedDemand: z.number(),
  }) },
  output: { schema: ForecastOutputSchema.omit({ sku: true, forecastedDemand: true }) },
  prompt: `
    You are an expert inventory analyst. You have performed a linear regression on historical sales data for a product. Your task is to interpret the results and create a user-friendly forecast.

    **Product SKU:** {{{sku}}}
    **Forecast Period:** {{{daysToForecast}}} days
    **Linear Regression Results:**
    - Slope: {{{slope}}} (units per day change)
    - Intercept: {{{intercept}}}
    - Data Points: {{{dataPointCount}}} days of sales data

    **Calculated Forecast:**
    - Estimated units to be sold: {{{forecastedDemand}}}

    **Your Task:**
    1.  **Determine Trend:**
        - If slope is significantly positive (e.g., > 0.1), the trend is 'Upward'.
        - If slope is significantly negative (e.g., < -0.1), the trend is 'Downward'.
        - Otherwise, the trend is 'Stable'.
    2.  **Determine Confidence:**
        - If 'dataPointCount' is high (e.g., > 90), confidence is 'High'.
        - If 'dataPointCount' is moderate (e.g., 30-90), confidence is 'Medium'.
        - If 'dataPointCount' is low (e.g., < 30), confidence is also 'Low'. Confidence is also 'Low' if the slope is very steep, indicating volatile sales.
    3.  **Write Analysis:**
        - Write a concise, 1-2 sentence summary. Start with the trend.
        - Example (Upward): "Sales for this product show a clear upward trend. Based on this, I predict you will sell approximately {{forecastedDemand}} units in the next {{daysToForecast}} days."
        - Example (Stable): "This product has stable sales with no significant trend. The forecast for the next {{daysToForecast}} days is around {{forecastedDemand}} units."
        - Example (Low Confidence): "With limited historical data, the forecast is less certain. However, based on recent activity, the estimate for the next {{daysToForecast}} days is {{forecastedDemand}} units."

    Provide your response in the specified JSON format.
  `,
});

export const productDemandForecastFlow = ai.defineFlow(
  {
    name: 'productDemandForecastFlow',
    inputSchema: ForecastInputSchema,
    outputSchema: ForecastOutputSchema,
  },
  async ({ companyId, sku, daysToForecast }): Promise<z.infer<typeof ForecastOutputSchema>> => {
    try {
      const historicalData = await getHistoricalSalesForSingleSkuFromDB(companyId, sku);
      
      if (historicalData.length < 5) {
        return {
          sku,
          forecastedDemand: 0,
          confidence: 'Low',
          analysis: "There is not enough historical sales data for this product to generate a reliable forecast.",
          trend: 'Stable',
        };
      }

      const firstDay = new Date(historicalData[0].sale_date);
      const dataForRegression = historicalData.map((d: { sale_date: string; total_quantity: number }) => ({
        x: differenceInDays(new Date(d.sale_date), firstDay),
        y: d.total_quantity,
      }));

      const { slope, intercept } = linearRegression(dataForRegression);

      // Predict for the next 'daysToForecast' days
      let forecastedDemand = 0;
      const lastDayX = dataForRegression[dataForRegression.length - 1].x;
      for (let i = 1; i <= daysToForecast; i++) {
        const futureX = lastDayX + i;
        const predictedY = slope * futureX + intercept;
        forecastedDemand += Math.max(0, predictedY); // Don't forecast negative sales
      }
      
      const roundedForecast = Math.round(forecastedDemand);

      const { output } = await generateForecastAnalysisPrompt({
        sku,
        daysToForecast,
        slope,
        intercept,
        dataPointCount: historicalData.length,
        forecastedDemand: roundedForecast,
      }, { model: config.ai.model });

      if (!output) {
        throw new Error("AI failed to generate a forecast analysis.");
      }
      
      return {
        sku,
        forecastedDemand: roundedForecast,
        ...output,
      };

    } catch (e) {
      logError(e, { context: `[Demand Forecast Flow] Failed for SKU ${sku} in company ${companyId}` });
      throw new Error("An error occurred while generating the demand forecast.");
    }
  }
);


export const getProductDemandForecast = ai.defineTool(
    {
        name: 'getProductDemandForecast',
        description: "Analyzes historical sales for a SINGLE product SKU to forecast future demand. Use this when asked to 'forecast demand', 'predict sales', or 'what will I sell' for a specific product.",
        inputSchema: ForecastInputSchema,
        outputSchema: ForecastOutputSchema,
    },
    async (input) => productDemandForecastFlow(input)
);
