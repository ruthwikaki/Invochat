import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock dependencies first (must be hoisted)
vi.mock('@/services/enhanced-demand-forecasting');
vi.mock('@/ai/genkit', () => ({
  ai: {
    defineTool: vi.fn().mockImplementation((_config, handler) => handler),
    defineFlow: vi.fn().mockImplementation((_config, handler) => handler),
    definePrompt: vi.fn().mockImplementation((config) => config),
  },
}));
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config');

// Import the mocked service and actual functions
import { enhancedForecastingService } from '@/services/enhanced-demand-forecasting';
import { getEnhancedDemandForecast, getCompanyForecastSummary } from '@/ai/flows/enhanced-forecasting-tools';

// Type the mocked service
const mockEnhancedForecastingService = vi.mocked(enhancedForecastingService);

describe('Enhanced Forecasting Tools', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('getEnhancedDemandForecast', () => {
    it('should generate enhanced forecast for single product', async () => {
      const mockServiceForecast = {
        sku: 'PROD-001',
        productName: 'Test Product',
        forecastPeriodDays: 90,
        confidence: 0.85,
        lastUpdated: '2024-01-15T10:00:00Z',
        predictions: {
          daily: Array(30).fill(5).map((val, i) => val + (i % 5)), // Create 30 days with pattern [5,6,7,8,9,5,6,7,8,9,...]
          weekly: [35, 40, 38],
          monthly: [150, 160, 140],
        },
        seasonalPatterns: [
          {
            month: 12,
            seasonalityFactor: 1.5,
            historicalAverage: 150,
            confidence: 0.85,
          },
        ],
        modelUsed: {
          name: 'Hybrid ML Model',
          algorithm: 'hybrid' as const,
          accuracy: 0.89,
          confidence: 0.87,
        },
        inventoryOptimization: {
          currentStock: 100,
          recommendedReorderPoint: 25,
          recommendedReorderQuantity: 75,
          safetyStockDays: 14,
          stockoutRisk: 'low' as const,
          expectedDepleteDate: '2024-02-15',
        },
        businessInsights: {
          trend: 'increasing' as const,
          seasonality: 'medium' as const,
          riskFactors: ['seasonal demand variation'],
          opportunities: ['holiday season boost'],
          recommendations: ['increase stock before holidays'],
        },
      };

      const expectedForecast = {
        sku: 'PROD-001',
        productName: 'Test Product',
        forecastSummary: {
          dailyAverage: 7,
          weeklyAverage: 35,
          monthlyProjection: 150,
          confidence: 85,
          trend: 'increasing',
          seasonality: 'medium'
        },
        inventoryInsights: {
          currentStock: 100,
          stockoutRisk: 'low',
          expectedDepleteDate: '2024-02-15',
          recommendedReorderPoint: 25,
          recommendedReorderQuantity: 75
        },
        keyInsights: {
          riskFactors: ['seasonal demand variation'],
          opportunities: ['holiday season boost'],
          recommendations: ['increase stock before holidays']
        },
        modelInfo: {
          algorithm: 'hybrid',
          accuracy: 89
        }
      };

      mockEnhancedForecastingService.generateEnhancedForecast.mockResolvedValue(mockServiceForecast);

      const result = await getEnhancedDemandForecast({
        companyId: 'test-company-id',
        sku: 'PROD-001',
        forecastDays: 90,
      });

      expect(result).toEqual(expectedForecast);
      expect(mockEnhancedForecastingService.generateEnhancedForecast).toHaveBeenCalledWith(
        'test-company-id',
        'PROD-001',
        90
      );
    });

    it('should handle errors gracefully', async () => {
      mockEnhancedForecastingService.generateEnhancedForecast.mockRejectedValue(
        new Error('Forecast generation failed')
      );

      const result = await getEnhancedDemandForecast({
        companyId: 'test-company-id',
        sku: 'PROD-001',
        forecastDays: 90,
      });

      expect(result).toEqual({
        error: "Failed to generate enhanced forecast",
        sku: 'PROD-001',
        recommendation: "Please try again or check if the product exists"
      });
    });
  });

  describe('getCompanyForecastSummary', () => {
    it('should generate company-wide forecast summary', async () => {
      const mockServiceSummary = {
        companyId: 'test-company-id',
        totalProducts: 50,
        forecastAccuracy: 0.85,
        overallTrend: 'stable' as const,
        lastAnalyzed: '2024-01-15T10:00:00Z',
        topRisks: [
          {
            sku: 'PROD-001',
            productName: 'High Risk Product',
            risk: 'stockout risk',
            severity: 'high' as const,
          },
        ],
        topOpportunities: [
          {
            sku: 'PROD-001',
            productName: 'High Demand Product',
            opportunity: 'Scale inventory',
            potential: 15000,
          },
        ],
        seasonalInsights: ['Q4 shows 20% increase'],
      };

      const expectedSummary = {
        companyOverview: {
          totalProductsAnalyzed: 50,
          overallForecastAccuracy: 85,
          overallTrend: 'stable',
          analysisDate: '2024-01-15T10:00:00Z'
        },
        riskAnalysis: {
          highRiskProducts: 1,
          mediumRiskProducts: 0,
          topRisks: [
            {
              sku: 'PROD-001',
              productName: 'High Risk Product',
              risk: 'stockout risk',
              severity: 'high',
            },
          ]
        },
        opportunityAnalysis: {
          totalOpportunities: 1,
          topOpportunities: [
            {
              sku: 'PROD-001',
              productName: 'High Demand Product',
              opportunity: 'Scale inventory',
              potential: 15000,
            },
          ]
        },
        seasonalInsights: ['Q4 shows 20% increase'],
        strategicRecommendations: ['Strong seasonal patterns detected - implement seasonal inventory planning']
      };

      mockEnhancedForecastingService.generateCompanyForecastSummary.mockResolvedValue(mockServiceSummary);

      const result = await getCompanyForecastSummary({
        companyId: 'test-company-id',
      });

      expect(result).toEqual(expectedSummary);
      expect(mockEnhancedForecastingService.generateCompanyForecastSummary).toHaveBeenCalledWith(
        'test-company-id'
      );
    });

    it('should handle service errors', async () => {
      mockEnhancedForecastingService.generateCompanyForecastSummary.mockRejectedValue(
        new Error('Summary generation failed')
      );

      const result = await getCompanyForecastSummary({
        companyId: 'test-company-id',
      });

      expect(result).toEqual({
        error: "Failed to generate company forecast summary",
        recommendation: "Please try again or contact support"
      });
    });
  });
});
