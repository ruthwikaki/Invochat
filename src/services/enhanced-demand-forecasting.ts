/**
 * @fileOverview Enhanced demand forecasting service with machine learning algorithms,
 * seasonal pattern recognition, and advanced inventory optimization
 */

import { getHistoricalSalesForSingleSkuFromDB, getUnifiedInventoryFromDB } from '@/services/database';
import { linearRegression } from '@/lib/utils';
import { logError } from '@/lib/error-handler';
import { differenceInDays, format } from 'date-fns';

// Types for enhanced forecasting
export interface SeasonalPattern {
  month: number;
  seasonalityFactor: number;
  historicalAverage: number;
  confidence: number;
}

export interface ForecastingModel {
  name: string;
  algorithm: 'linear' | 'exponential' | 'seasonal' | 'hybrid';
  accuracy: number;
  confidence: number;
}

export interface EnhancedForecast {
  sku: string;
  productName: string;
  forecastPeriodDays: number;
  predictions: {
    daily: number[];
    weekly: number[];
    monthly: number[];
  };
  seasonalPatterns: SeasonalPattern[];
  modelUsed: ForecastingModel;
  inventoryOptimization: {
    currentStock: number;
    recommendedReorderPoint: number;
    recommendedReorderQuantity: number;
    safetyStockDays: number;
    stockoutRisk: 'low' | 'medium' | 'high';
    expectedDepleteDate: string | null;
  };
  businessInsights: {
    trend: 'increasing' | 'decreasing' | 'stable' | 'volatile';
    seasonality: 'high' | 'medium' | 'low' | 'none';
    riskFactors: string[];
    opportunities: string[];
    recommendations: string[];
  };
  confidence: number;
  lastUpdated: string;
}

export interface CompanyForecastSummary {
  companyId: string;
  totalProducts: number;
  forecastAccuracy: number;
  topRisks: Array<{
    sku: string;
    productName: string;
    risk: string;
    severity: 'high' | 'medium' | 'low';
  }>;
  topOpportunities: Array<{
    sku: string;
    productName: string;
    opportunity: string;
    potential: number;
  }>;
  overallTrend: 'growth' | 'decline' | 'stable';
  seasonalInsights: string[];
  lastAnalyzed: string;
}

/**
 * Advanced mathematical functions for forecasting
 */

// Exponential smoothing for trend analysis
export function exponentialSmoothing(data: number[], alpha: number = 0.3): number[] {
  if (data.length === 0) return [];
  
  const smoothed = [data[0]];
  for (let i = 1; i < data.length; i++) {
    smoothed[i] = alpha * data[i] + (1 - alpha) * smoothed[i - 1];
  }
  return smoothed;
}

// Seasonal decomposition using moving averages
export function detectSeasonalPatterns(monthlyData: Array<{ month: number; value: number }>): SeasonalPattern[] {
  const patterns: SeasonalPattern[] = [];
  
  // Group by month across multiple years
  const monthlyGroups = new Map<number, number[]>();
  monthlyData.forEach(({ month, value }) => {
    if (!monthlyGroups.has(month)) {
      monthlyGroups.set(month, []);
    }
    monthlyGroups.get(month)!.push(value);
  });
  
  // Calculate seasonal factors
  const overallAverage = monthlyData.reduce((sum, d) => sum + d.value, 0) / monthlyData.length;
  
  for (let month = 1; month <= 12; month++) {
    const monthData = monthlyGroups.get(month) || [];
    if (monthData.length > 0) {
      const monthAverage = monthData.reduce((sum, val) => sum + val, 0) / monthData.length;
      const seasonalityFactor = monthAverage / (overallAverage || 1);
      const variance = monthData.reduce((acc, val) => acc + Math.pow(val - monthAverage, 2), 0) / monthData.length;
      const confidence = Math.max(0.1, Math.min(0.95, 1 - (Math.sqrt(variance) / (monthAverage + 1))));
      
      patterns.push({
        month,
        seasonalityFactor,
        historicalAverage: monthAverage,
        confidence
      });
    }
  }
  
  return patterns;
}

// Hybrid forecasting model that combines multiple algorithms
export function hybridForecast(
  historicalData: Array<{ date: Date; value: number }>,
  daysToForecast: number
): { predictions: number[]; confidence: number; modelUsed: ForecastingModel } {
  if (historicalData.length < 7) {
    return {
      predictions: Array(daysToForecast).fill(0),
      confidence: 0.1,
      modelUsed: { name: 'Insufficient Data', algorithm: 'linear', accuracy: 0.1, confidence: 0.1 }
    };
  }
  
  const values = historicalData.map(d => d.value);
  
  // Model 1: Linear regression
  const regressionData = historicalData.map((d, i) => ({
    x: i,
    y: d.value
  }));
  const { slope, intercept } = linearRegression(regressionData);
  const linearPredictions: number[] = [];
  for (let i = 0; i < daysToForecast; i++) {
    const futureX = historicalData.length + i;
    linearPredictions.push(Math.max(0, slope * futureX + intercept));
  }
  
  // Model 2: Exponential smoothing
  const smoothed = exponentialSmoothing(values);
  const trend = smoothed[smoothed.length - 1] - smoothed[Math.max(0, smoothed.length - 7)];
  const exponentialPredictions: number[] = [];
  let lastValue = smoothed[smoothed.length - 1];
  for (let i = 0; i < daysToForecast; i++) {
    lastValue += trend * 0.1; // Damped trend
    exponentialPredictions.push(Math.max(0, lastValue));
  }
  
  // Model 3: Seasonal adjustment if enough data
  const monthlyData = aggregateDataByMonth(historicalData);
  const seasonalPatterns = detectSeasonalPatterns(monthlyData);
  
  // Calculate model accuracies
  const linearAccuracy = calculateModelAccuracy(values, linearPredictions.slice(0, Math.min(values.length, 30)));
  const exponentialAccuracy = calculateModelAccuracy(values, exponentialPredictions.slice(0, Math.min(values.length, 30)));
  
  // Hybrid approach: weight models based on accuracy
  const linearWeight = linearAccuracy / (linearAccuracy + exponentialAccuracy + 0.01);
  const exponentialWeight = 1 - linearWeight;
  
  const hybridPredictions = linearPredictions.map((linear, i) => {
    const exponential = exponentialPredictions[i] || 0;
    return linear * linearWeight + exponential * exponentialWeight;
  });
  
  // Apply seasonal adjustment if patterns detected
  const seasonalAdjustedPredictions = hybridPredictions.map((pred, i) => {
    const futureDate = new Date();
    futureDate.setDate(futureDate.getDate() + i);
    const month = futureDate.getMonth() + 1;
    const pattern = seasonalPatterns.find(p => p.month === month);
    if (pattern && pattern.confidence > 0.3) {
      return pred * pattern.seasonalityFactor;
    }
    return pred;
  });
  
  const confidence = Math.min(0.95, Math.max(0.1, (linearAccuracy + exponentialAccuracy) / 2));
  
  return {
    predictions: seasonalAdjustedPredictions,
    confidence,
    modelUsed: {
      name: 'Hybrid ML Model',
      algorithm: 'hybrid',
      accuracy: confidence,
      confidence
    }
  };
}

// Helper functions
function aggregateDataByMonth(data: Array<{ date: Date; value: number }>): Array<{ month: number; value: number }> {
  const monthlyTotals = new Map<string, number>();
  
  data.forEach(({ date, value }) => {
    const key = `${date.getFullYear()}-${date.getMonth() + 1}`;
    monthlyTotals.set(key, (monthlyTotals.get(key) || 0) + value);
  });
  
  return Array.from(monthlyTotals.entries()).map(([key, value]) => ({
    month: parseInt(key.split('-')[1]),
    value
  }));
}

function calculateModelAccuracy(actual: number[], predicted: number[]): number {
  if (actual.length === 0 || predicted.length === 0) return 0.1;
  
  const minLength = Math.min(actual.length, predicted.length);
  let totalError = 0;
  let totalActual = 0;
  
  for (let i = 0; i < minLength; i++) {
    totalError += Math.abs(actual[i] - predicted[i]);
    totalActual += actual[i];
  }
  
  if (totalActual === 0) return 0.1;
  const mape = totalError / totalActual;
  return Math.max(0.1, Math.min(0.95, 1 - mape));
}

/**
 * Main enhanced forecasting service
 */
export class EnhancedDemandForecastingService {
  private static instance: EnhancedDemandForecastingService;
  
  static getInstance(): EnhancedDemandForecastingService {
    if (!this.instance) {
      this.instance = new EnhancedDemandForecastingService();
    }
    return this.instance;
  }
  
  async generateEnhancedForecast(
    companyId: string,
    sku: string,
    forecastDays: number = 90
  ): Promise<EnhancedForecast | null> {
    try {
      // Get historical sales data
      const historicalSales = await getHistoricalSalesForSingleSkuFromDB(companyId, sku);
      if (historicalSales.length < 5) {
        return null; // Insufficient data
      }
      
      // Get current inventory
      const { items: inventory } = await getUnifiedInventoryFromDB(companyId, { limit: 1000 });
      const product = inventory.find(p => p.sku === sku);
      if (!product) {
        return null;
      }
      
      // Convert historical data format
      const historicalData = historicalSales.map(sale => ({
        date: new Date(sale.sale_date),
        value: sale.total_quantity
      }));
      
      // Generate hybrid forecast
      const { predictions, confidence, modelUsed } = hybridForecast(historicalData, forecastDays);
      
      // Calculate weekly and monthly aggregates
      const weeklyPredictions: number[] = [];
      const monthlyPredictions: number[] = [];
      
      for (let i = 0; i < predictions.length; i += 7) {
        const weekSum = predictions.slice(i, i + 7).reduce((sum, val) => sum + val, 0);
        weeklyPredictions.push(weekSum);
      }
      
      for (let i = 0; i < predictions.length; i += 30) {
        const monthSum = predictions.slice(i, i + 30).reduce((sum, val) => sum + val, 0);
        monthlyPredictions.push(monthSum);
      }
      
      // Detect seasonal patterns
      const monthlyHistorical = aggregateDataByMonth(historicalData);
      const seasonalPatterns = detectSeasonalPatterns(monthlyHistorical);
      
      // Calculate inventory optimization
      const avgDailyDemand = predictions.slice(0, 30).reduce((sum, val) => sum + val, 0) / 30;
      const safetyStockDays = confidence < 0.5 ? 14 : confidence < 0.7 ? 10 : 7;
      const recommendedReorderPoint = avgDailyDemand * (7 + safetyStockDays); // Lead time + safety stock
      const recommendedReorderQuantity = avgDailyDemand * 60; // 2 months supply
      
      // Calculate expected depletion date
      let expectedDepleteDate: string | null = null;
      let runningStock = product.inventory_quantity || 0;
      for (let i = 0; i < predictions.length && runningStock > 0; i++) {
        runningStock -= predictions[i];
        if (runningStock <= 0) {
          const futureDate = new Date();
          futureDate.setDate(futureDate.getDate() + i);
          expectedDepleteDate = format(futureDate, 'yyyy-MM-dd');
          break;
        }
      }
      
      // Determine stockout risk
      const daysUntilStockout = expectedDepleteDate ? 
        differenceInDays(new Date(expectedDepleteDate), new Date()) : 999;
      const stockoutRisk: 'low' | 'medium' | 'high' = 
        daysUntilStockout < 14 ? 'high' : 
        daysUntilStockout < 30 ? 'medium' : 'low';
      
      // Business insights analysis
      const businessInsights = this.analyzeBusinessInsights(
        predictions,
        seasonalPatterns,
        confidence,
        stockoutRisk,
        product
      );
      
      return {
        sku,
        productName: product.product_title || sku,
        forecastPeriodDays: forecastDays,
        predictions: {
          daily: predictions,
          weekly: weeklyPredictions,
          monthly: monthlyPredictions
        },
        seasonalPatterns,
        modelUsed,
        inventoryOptimization: {
          currentStock: product.inventory_quantity || 0,
          recommendedReorderPoint,
          recommendedReorderQuantity,
          safetyStockDays,
          stockoutRisk,
          expectedDepleteDate
        },
        businessInsights,
        confidence,
        lastUpdated: new Date().toISOString()
      };
      
    } catch (error) {
      logError(error, { context: 'Enhanced demand forecasting failed', sku, companyId });
      return null;
    }
  }
  
  private analyzeBusinessInsights(
    predictions: number[],
    seasonalPatterns: SeasonalPattern[],
    confidence: number,
    stockoutRisk: 'low' | 'medium' | 'high',
    product: any
  ) {
    const recommendations: string[] = [];
    const riskFactors: string[] = [];
    const opportunities: string[] = [];
    
    // Trend analysis
    const earlyPredictions = predictions.slice(0, 30).reduce((sum, val) => sum + val, 0);
    const latePredictions = predictions.slice(30, 60).reduce((sum, val) => sum + val, 0);
    const trend = latePredictions > earlyPredictions * 1.1 ? 'increasing' :
                  latePredictions < earlyPredictions * 0.9 ? 'decreasing' : 'stable';
    
    // Seasonality analysis
    const maxSeasonality = Math.max(...seasonalPatterns.map(p => p.seasonalityFactor));
    const minSeasonality = Math.min(...seasonalPatterns.map(p => p.seasonalityFactor));
    const seasonalityRange = maxSeasonality - minSeasonality;
    const seasonality = seasonalityRange > 0.5 ? 'high' : 
                       seasonalityRange > 0.3 ? 'medium' : 
                       seasonalityRange > 0.1 ? 'low' : 'none';
    
    // Generate insights
    if (stockoutRisk === 'high') {
      riskFactors.push('High stockout risk within 2 weeks');
      recommendations.push('Expedite reorder immediately');
    }
    
    if (confidence < 0.5) {
      riskFactors.push('Low forecast confidence due to irregular sales pattern');
      recommendations.push('Monitor closely and adjust inventory levels frequently');
    }
    
    if (trend === 'increasing') {
      opportunities.push('Growing demand trend detected - consider inventory expansion');
      recommendations.push('Increase safety stock levels for this growth phase');
    }
    
    if (seasonality === 'high') {
      opportunities.push('Strong seasonal patterns - optimize inventory timing');
      recommendations.push('Plan inventory buildup before peak seasons');
    }
    
    if (product.inventory_quantity > predictions.slice(0, 60).reduce((sum: number, val: number) => sum + val, 0)) {
      opportunities.push('Current stock exceeds 2-month demand forecast');
      recommendations.push('Consider reallocating excess inventory or promotional activities');
    }
    
    return {
      trend: trend as 'increasing' | 'decreasing' | 'stable' | 'volatile',
      seasonality: seasonality as 'high' | 'medium' | 'low' | 'none',
      riskFactors,
      opportunities,
      recommendations
    };
  }
  
  async generateCompanyForecastSummary(companyId: string): Promise<CompanyForecastSummary> {
    try {
      const { items: products } = await getUnifiedInventoryFromDB(companyId, { limit: 100 });
      const forecasts: EnhancedForecast[] = [];
      
      // Generate forecasts for top products
      for (const product of products.slice(0, 50)) {
        const forecast = await this.generateEnhancedForecast(companyId, product.sku, 90);
        if (forecast) {
          forecasts.push(forecast);
        }
      }
      
      // Analyze company-wide trends
      const avgAccuracy = forecasts.reduce((sum, f) => sum + f.confidence, 0) / forecasts.length;
      const increasingTrends = forecasts.filter(f => f.businessInsights.trend === 'increasing').length;
      const decreasingTrends = forecasts.filter(f => f.businessInsights.trend === 'decreasing').length;
      
      const overallTrend = increasingTrends > decreasingTrends ? 'growth' :
                          decreasingTrends > increasingTrends ? 'decline' : 'stable';
      
      // Extract top risks and opportunities
      const topRisks = forecasts
        .filter(f => f.inventoryOptimization.stockoutRisk === 'high' || f.businessInsights.riskFactors.length > 0)
        .slice(0, 10)
        .map(f => ({
          sku: f.sku,
          productName: f.productName,
          risk: f.businessInsights.riskFactors[0] || 'High stockout risk',
          severity: f.inventoryOptimization.stockoutRisk
        }));
      
      const topOpportunities = forecasts
        .filter(f => f.businessInsights.opportunities.length > 0)
        .slice(0, 10)
        .map(f => ({
          sku: f.sku,
          productName: f.productName,
          opportunity: f.businessInsights.opportunities[0],
          potential: f.predictions.monthly[0] || 0
        }));
      
      // Seasonal insights
      const seasonalInsights: string[] = [];
      const highSeasonalityProducts = forecasts.filter(f => f.businessInsights.seasonality === 'high');
      if (highSeasonalityProducts.length > 0) {
        seasonalInsights.push(`${highSeasonalityProducts.length} products show strong seasonal patterns`);
      }
      
      return {
        companyId,
        totalProducts: forecasts.length,
        forecastAccuracy: avgAccuracy,
        topRisks,
        topOpportunities,
        overallTrend,
        seasonalInsights,
        lastAnalyzed: new Date().toISOString()
      };
      
    } catch (error) {
      logError(error, { context: 'Company forecast summary failed', companyId });
      return {
        companyId,
        totalProducts: 0,
        forecastAccuracy: 0,
        topRisks: [],
        topOpportunities: [],
        overallTrend: 'stable',
        seasonalInsights: [],
        lastAnalyzed: new Date().toISOString()
      };
    }
  }
}

// Export singleton instance
export const enhancedForecastingService = EnhancedDemandForecastingService.getInstance();
