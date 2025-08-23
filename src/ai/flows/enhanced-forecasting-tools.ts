'use server';
/**
 * @fileOverview Enhanced AI tools for advanced demand forecasting with ML capabilities
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { enhancedForecastingService } from '@/services/enhanced-demand-forecasting';
import { logError } from '@/lib/error-handler';
import { config } from '@/config/app-config';

// Input schemas
const EnhancedForecastInputSchema = z.object({
  companyId: z.string().uuid(),
  sku: z.string().describe("The SKU of the product to forecast demand for"),
  forecastDays: z.number().int().positive().default(90).describe("Number of days to forecast (default: 90)")
});

const CompanyForecastInputSchema = z.object({
  companyId: z.string().uuid()
});

const BulkForecastInputSchema = z.object({
  companyId: z.string().uuid(),
  skus: z.array(z.string()).describe("Array of SKUs to forecast"),
  forecastDays: z.number().int().positive().default(90).describe("Number of days to forecast (default: 90)")
});

// Output schemas
const EnhancedForecastOutputSchema = z.any(); // Complex nested structure
const CompanyForecastSummarySchema = z.any(); // Complex nested structure

/**
 * Enhanced demand forecasting tool with machine learning
 */
export const getEnhancedDemandForecast = ai.defineTool(
  {
    name: 'getEnhancedDemandForecast',
    description: "Generate advanced ML-powered demand forecast for a specific product with seasonal patterns, inventory optimization, and business insights. Use this for detailed forecasting analysis.",
    inputSchema: EnhancedForecastInputSchema,
    outputSchema: EnhancedForecastOutputSchema,
  },
  async ({ companyId, sku, forecastDays }) => {
    try {
      const forecast = await enhancedForecastingService.generateEnhancedForecast(
        companyId,
        sku,
        forecastDays
      );

      if (!forecast) {
        return {
          error: "Unable to generate enhanced forecast - insufficient historical data",
          sku,
          recommendation: "Please ensure the product has at least 5 historical sales records"
        };
      }

      // Simplify the output for AI consumption while preserving key insights
      return {
        sku: forecast.sku,
        productName: forecast.productName,
        forecastSummary: {
          dailyAverage: Math.round(forecast.predictions.daily.slice(0, 30).reduce((sum, val) => sum + val, 0) / 30 * 100) / 100,
          weeklyAverage: Math.round(forecast.predictions.weekly[0] || 0),
          monthlyProjection: Math.round(forecast.predictions.monthly[0] || 0),
          confidence: Math.round(forecast.confidence * 100),
          trend: forecast.businessInsights.trend,
          seasonality: forecast.businessInsights.seasonality
        },
        inventoryInsights: {
          currentStock: forecast.inventoryOptimization.currentStock,
          stockoutRisk: forecast.inventoryOptimization.stockoutRisk,
          expectedDepleteDate: forecast.inventoryOptimization.expectedDepleteDate,
          recommendedReorderPoint: Math.round(forecast.inventoryOptimization.recommendedReorderPoint),
          recommendedReorderQuantity: Math.round(forecast.inventoryOptimization.recommendedReorderQuantity)
        },
        keyInsights: {
          riskFactors: forecast.businessInsights.riskFactors,
          opportunities: forecast.businessInsights.opportunities,
          recommendations: forecast.businessInsights.recommendations
        },
        modelInfo: {
          algorithm: forecast.modelUsed.algorithm,
          accuracy: Math.round(forecast.modelUsed.accuracy * 100)
        }
      };

    } catch (error) {
      logError(error, { context: 'Enhanced demand forecast tool failed', sku, companyId });
      return {
        error: "Failed to generate enhanced forecast",
        sku,
        recommendation: "Please try again or check if the product exists"
      };
    }
  }
);

/**
 * Company-wide forecasting summary tool
 */
export const getCompanyForecastSummary = ai.defineTool(
  {
    name: 'getCompanyForecastSummary',
    description: "Get a comprehensive forecasting summary for the entire company including top risks, opportunities, and overall trends. Use this for strategic inventory planning.",
    inputSchema: CompanyForecastInputSchema,
    outputSchema: CompanyForecastSummarySchema,
  },
  async ({ companyId }) => {
    try {
      const summary = await enhancedForecastingService.generateCompanyForecastSummary(companyId);

      return {
        companyOverview: {
          totalProductsAnalyzed: summary.totalProducts,
          overallForecastAccuracy: Math.round(summary.forecastAccuracy * 100),
          overallTrend: summary.overallTrend,
          analysisDate: summary.lastAnalyzed
        },
        riskAnalysis: {
          highRiskProducts: summary.topRisks.filter(r => r.severity === 'high').length,
          mediumRiskProducts: summary.topRisks.filter(r => r.severity === 'medium').length,
          topRisks: summary.topRisks.slice(0, 5).map(risk => ({
            sku: risk.sku,
            productName: risk.productName,
            risk: risk.risk,
            severity: risk.severity
          }))
        },
        opportunityAnalysis: {
          totalOpportunities: summary.topOpportunities.length,
          topOpportunities: summary.topOpportunities.slice(0, 5).map(opp => ({
            sku: opp.sku,
            productName: opp.productName,
            opportunity: opp.opportunity,
            potential: Math.round(opp.potential)
          }))
        },
        seasonalInsights: summary.seasonalInsights,
        strategicRecommendations: generateStrategicRecommendations(summary)
      };

    } catch (error) {
      logError(error, { context: 'Company forecast summary tool failed', companyId });
      return {
        error: "Failed to generate company forecast summary",
        recommendation: "Please try again or contact support"
      };
    }
  }
);

/**
 * Bulk forecasting tool for multiple products
 */
export const getBulkEnhancedForecast = ai.defineTool(
  {
    name: 'getBulkEnhancedForecast',
    description: "Generate enhanced forecasts for multiple products at once. Useful for category analysis or when comparing multiple SKUs.",
    inputSchema: BulkForecastInputSchema,
    outputSchema: z.any(),
  },
  async ({ companyId, skus, forecastDays }) => {
    try {
      const forecasts = await Promise.all(
        skus.slice(0, 20).map(async (sku) => { // Limit to 20 to avoid timeout
          try {
            const forecast = await enhancedForecastingService.generateEnhancedForecast(
              companyId,
              sku,
              forecastDays
            );
            
            if (!forecast) return null;
            
            return {
              sku: forecast.sku,
              productName: forecast.productName,
              monthlyProjection: Math.round(forecast.predictions.monthly[0] || 0),
              confidence: Math.round(forecast.confidence * 100),
              trend: forecast.businessInsights.trend,
              stockoutRisk: forecast.inventoryOptimization.stockoutRisk,
              opportunities: forecast.businessInsights.opportunities.length,
              risks: forecast.businessInsights.riskFactors.length
            };
          } catch (error) {
            logError(error, { context: 'Bulk forecast item failed', sku });
            return null;
          }
        })
      );

      const validForecasts = forecasts.filter(f => f !== null);
      
      // Aggregate insights
      const highRiskCount = validForecasts.filter(f => f.stockoutRisk === 'high').length;
      const growthTrendCount = validForecasts.filter(f => f.trend === 'increasing').length;
      const avgConfidence = validForecasts.reduce((sum, f) => sum + f.confidence, 0) / validForecasts.length;

      return {
        summary: {
          requestedProducts: skus.length,
          analyzedProducts: validForecasts.length,
          averageConfidence: Math.round(avgConfidence),
          highRiskProducts: highRiskCount,
          growthTrendProducts: growthTrendCount
        },
        products: validForecasts,
        recommendations: [
          highRiskCount > 0 ? `${highRiskCount} products have high stockout risk - review immediately` : null,
          growthTrendCount > 0 ? `${growthTrendCount} products show growth trends - consider increasing inventory` : null,
          avgConfidence < 70 ? "Low average forecast confidence - consider gathering more historical data" : null
        ].filter(Boolean)
      };

    } catch (error) {
      logError(error, { context: 'Bulk enhanced forecast tool failed', companyId });
      return {
        error: "Failed to generate bulk forecasts",
        recommendation: "Please try with fewer SKUs or try again later"
      };
    }
  }
);

/**
 * Helper function to generate strategic recommendations
 */
function generateStrategicRecommendations(summary: any): string[] {
  const recommendations: string[] = [];
  
  if (summary.topRisks.length > 5) {
    recommendations.push("High number of at-risk products detected - implement automated reorder alerts");
  }
  
  if (summary.overallTrend === 'growth') {
    recommendations.push("Company-wide growth trend detected - consider expanding inventory capacity");
  } else if (summary.overallTrend === 'decline') {
    recommendations.push("Declining trend observed - review product portfolio and marketing strategies");
  }
  
  if (summary.forecastAccuracy < 0.7) {
    recommendations.push("Forecast accuracy below 70% - consider improving data quality and collection");
  }
  
  if (summary.seasonalInsights.length > 0) {
    recommendations.push("Strong seasonal patterns detected - implement seasonal inventory planning");
  }
  
  if (summary.topOpportunities.length > 3) {
    recommendations.push("Multiple growth opportunities identified - prioritize high-potential products");
  }
  
  return recommendations.length > 0 ? recommendations : [
    "Current forecasting performance is stable - continue monitoring key metrics"
  ];
}

/**
 * Enhanced forecasting flow that uses AI to interpret results
 */
export const enhancedForecastingFlow = ai.defineFlow(
  {
    name: 'enhancedForecastingFlow',
    inputSchema: z.object({
      companyId: z.string().uuid(),
      query: z.string().describe("Natural language query about forecasting needs"),
      context: z.object({
        skus: z.array(z.string()).optional(),
        timeframe: z.string().optional(),
        analysisType: z.enum(['single', 'bulk', 'company']).optional()
      }).optional()
    }),
    outputSchema: z.object({
      analysis: z.string(),
      recommendations: z.array(z.string()),
      data: z.any(),
      confidence: z.number()
    })
  },
  async ({ companyId, query, context }) => {
    try {
      // Use AI to interpret the query and determine appropriate action
      const analysisPrompt = ai.definePrompt({
        name: 'interpretForecastingQuery',
        input: { schema: z.object({ query: z.string(), context: z.any() }) },
        output: { 
          schema: z.object({
            action: z.enum(['single_forecast', 'bulk_forecast', 'company_summary']),
            reasoning: z.string(),
            parameters: z.any()
          })
        },
        prompt: `
          You are an expert inventory analyst. Analyze this forecasting query and determine the best approach:
          
          Query: {{{query}}}
          Context: {{{json context}}}
          
          Choose the most appropriate action:
          - single_forecast: For specific product forecasting
          - bulk_forecast: For multiple products or category analysis  
          - company_summary: For overall business trend analysis
          
          Extract relevant parameters like SKUs, timeframes, etc.
        `
      });

      const { output: interpretation } = await analysisPrompt({ query, context }, { model: config.ai.model });
      
      if (!interpretation) {
        throw new Error("Failed to interpret forecasting query");
      }

      let data: any = {};
      let analysis = "";
      let recommendations: string[] = [];

      // Execute the determined action
      switch (interpretation.action) {
        case 'single_forecast':
          if (context?.skus?.[0]) {
            data = await getEnhancedDemandForecast({ 
              companyId, 
              sku: context.skus[0], 
              forecastDays: 90 
            });
            analysis = `Enhanced forecast generated for ${data.productName || context.skus[0]}. `;
            analysis += `Expected to sell ${data.forecastSummary?.monthlyProjection || 0} units next month with ${data.forecastSummary?.confidence || 0}% confidence.`;
          }
          break;
          
        case 'bulk_forecast':
          if (context?.skus && context.skus.length > 1) {
            data = await getBulkEnhancedForecast({ 
              companyId, 
              skus: context.skus, 
              forecastDays: 90 
            });
            analysis = `Bulk forecast analysis completed for ${data.summary?.analyzedProducts || 0} products. `;
            analysis += `Average confidence: ${data.summary?.averageConfidence || 0}%. `;
            analysis += `${data.summary?.highRiskProducts || 0} products at high stockout risk.`;
          }
          break;
          
        case 'company_summary':
          data = await getCompanyForecastSummary({ companyId });
          analysis = `Company-wide forecast analysis completed. Overall trend: ${data.companyOverview?.overallTrend || 'stable'}. `;
          analysis += `${data.riskAnalysis?.highRiskProducts || 0} high-risk products identified. `;
          analysis += `${data.opportunityAnalysis?.totalOpportunities || 0} growth opportunities detected.`;
          break;
      }

      // Extract recommendations from the data
      if (data.recommendations) {
        recommendations = Array.isArray(data.recommendations) ? data.recommendations : [data.recommendations];
      } else if (data.keyInsights?.recommendations) {
        recommendations = data.keyInsights.recommendations;
      } else if (data.strategicRecommendations) {
        recommendations = data.strategicRecommendations;
      }

      return {
        analysis: analysis || interpretation.reasoning,
        recommendations: recommendations.slice(0, 5), // Limit to top 5
        data,
        confidence: data.forecastSummary?.confidence || data.companyOverview?.overallForecastAccuracy || 75
      };

    } catch (error) {
      logError(error, { context: 'Enhanced forecasting flow failed', companyId, query });
      return {
        analysis: "I encountered an issue generating the forecast analysis. Please try again with a more specific request.",
        recommendations: ["Ensure products have sufficient historical sales data", "Try analyzing a specific product SKU"],
        data: { error: "Forecasting analysis failed" },
        confidence: 0
      };
    }
  }
);
