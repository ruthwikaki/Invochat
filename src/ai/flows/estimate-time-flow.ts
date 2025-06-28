
'use server';
/**
 * @fileOverview A predictive analytics flow for forecasting and trend analysis.
 * - predictiveAnalyticsFlow - A function that handles forecasting and other predictions.
 * - PredictiveQuerySchema - The input type for the predictiveAnalyticsFlow function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'zod';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { linearRegression } from '@/lib/utils';


const PredictiveQuerySchema = z.object({
  type: z.enum(['forecast', 'trend', 'seasonality', 'anomaly']),
  metric: z.string(),
  timeframe: z.string(),
  companyId: z.string(),
});

const PredictiveOutputSchema = z.object({
    prediction: z.any(),
    confidence: z.number(),
    factors: z.array(z.string()),
    recommendations: z.array(z.string()),
});

export async function getPrediction(input: z.infer<typeof PredictiveQuerySchema>): Promise<z.infer<typeof PredictiveOutputSchema>> {
  return predictiveAnalyticsFlow(input);
}

export const predictiveAnalyticsFlow = ai.defineFlow(
  {
    name: 'predictiveAnalytics',
    inputSchema: PredictiveQuerySchema,
    outputSchema: PredictiveOutputSchema,
  },
  async (input) => {
    // This is a placeholder implementation for demonstration.
    // A real implementation would involve complex time-series analysis.
    const { companyId, metric, timeframe, type } = input;
    const supabase = supabaseAdmin;
    if (!supabase) {
        throw new Error('Supabase admin client not initialized.');
    }
    
    // For now, let's just handle a simple sales forecast.
    if (type !== 'forecast' || metric !== 'sales') {
        return {
            prediction: { error: 'This predictive model currently only supports sales forecasting.' },
            confidence: 0.2,
            factors: ['Model limitation'],
            recommendations: ['Try asking to "forecast sales".'],
        };
    }
    
    // Simplified data fetching
    const { data } = await supabase.rpc('execute_dynamic_query', {
        query_text: `SELECT sale_date as date, total_amount as value FROM sales WHERE company_id = '${companyId}' ORDER BY sale_date ASC LIMIT 100`
    });

    if (!data || !Array.isArray(data) || data.length < 2) {
        return {
            prediction: { error: 'Not enough historical data to make a forecast.' },
            confidence: 0.1,
            factors: ['Insufficient data'],
            recommendations: ['Ensure you have at least two sales records.'],
        }
    }

    const timeSeries = data.map((d: any, i: number) => ({ x: i, y: d.value }));
    const { slope, intercept } = linearRegression(timeSeries);
    
    // "Predict" the next 5 periods
    const lastX = timeSeries.length - 1;
    const forecast = [];
    for (let i = 1; i <= 5; i++) {
        forecast.push({ period: `+${i}`, value: Math.max(0, slope * (lastX + i) + intercept).toFixed(2) });
    }

    return {
        prediction: {
            summary: `Based on a simple linear trend, sales are projected to be around $${parseFloat(forecast[0].value).toLocaleString()} in the next period.`,
            forecast,
        },
        confidence: 0.65, // Low confidence because it's a simple model
        factors: ['Based on a simple linear regression of the last 100 sales.'],
        recommendations: ['For a more accurate forecast, consider seasonal trends and external market factors.'],
    };
  }
);
