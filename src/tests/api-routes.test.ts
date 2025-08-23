import { describe, it, expect, beforeEach, vi } from 'vitest';
import { GET } from '@/app/api/analytics/advanced/route';
import { GET as AIAnalyticsGET, POST as AIAnalyticsPOST } from '@/app/api/ai-analytics/route';
import { NextRequest } from 'next/server';

// Helper to create NextRequest for testing
const createRequest = (url: string, init?: any): NextRequest => {
  return new NextRequest(url, init || {});
};

// Mock the auth helpers
vi.mock('@/lib/auth-helpers', () => ({
  requireUser: vi.fn(() => Promise.resolve({
    data: {
      user: { id: 'test-user-123', email: 'test@example.com' }
    }
  })),
  requireCompanyId: vi.fn(() => Promise.resolve('test-company-123'))
}));

// Mock the database functions
vi.mock('@/services/database', () => ({
  getAbcAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      total_revenue: 10000,
      category: 'A',
      revenue_contribution: 25.5
    }
  ])),
  getDemandForecastFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      forecasted_demand: 150,
      confidence: 85,
      trend: 'increasing'
    }
  ])),
  getSalesVelocityFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      units_per_day: 5.2,
      velocity_score: 8.5,
      trend: 'accelerating'
    }
  ])),
  getGrossMarginAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      gross_margin_percentage: 35.5,
      revenue: 10000,
      cost: 6450,
      profit: 3550,
      quantity_sold: 100,
      margin_per_unit: 35.50
    }
  ])),
  getHiddenRevenueOpportunitiesFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      type: 'price_optimization',
      opportunity_score: 75,
      potential_value: 2500,
      reasoning: 'Price optimization opportunity',
      suggested_action: 'Increase price by 10%'
    }
  ])),
  getSupplierPerformanceScoreFromDB: vi.fn(() => Promise.resolve([
    {
      supplier_name: 'Test Supplier',
      overall_score: 8.5,
      stock_performance_score: 9.0,
      cost_performance_score: 8.0,
      reliability_score: 8.5,
      performance_grade: 'A',
      recommendation: 'Excellent supplier'
    }
  ])),
  getInventoryTurnoverAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product',
      turnover_ratio: 4.2,
      days_sales_in_inventory: 87,
      performance_rating: 'Good',
      recommendation: 'Maintain current levels'
    }
  ])),
  getCustomerBehaviorInsightsFromDB: vi.fn(() => Promise.resolve([
    {
      segment: 'high_value',
      total_orders: 25,
      average_order_value: 125.50,
      purchase_frequency_per_month: 2.5,
      preferred_category: 'Electronics',
      customer_lifetime_value: 3000,
      recommendation: 'Focus on retention'
    }
  ])),
  getMultiChannelFeeAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      channel_name: 'Shopify',
      total_sales: 50000,
      total_fees: 1500,
      fee_percentage: 3.0,
      net_profit: 48500,
      profit_margin: 97.0,
      recommendation: 'Highly profitable channel'
    }
  ]))
}));

// Mock the AI flows
vi.mock('@/ai/flows', () => ({
  suggestBundlesFlow: vi.fn(() => Promise.resolve({
    suggestions: [
      {
        bundleName: 'Test Bundle',
        productSkus: ['TEST-001', 'TEST-002'],
        reasoning: 'Test reasoning',
        potentialBenefit: 'Test benefit',
        suggestedPrice: 99.99,
        estimatedDemand: 100,
        profitMargin: 35,
        seasonalFactors: ['Holiday'],
        targetCustomerSegment: 'General',
        crossSellOpportunity: 25
      }
    ],
    analysis: 'Test analysis',
    totalPotentialRevenue: 9999,
    implementationRecommendations: ['Test recommendation']
  })),
  economicImpactFlow: vi.fn(() => Promise.resolve({
    analysis: {
      scenario: 'Test scenario',
      revenueImpact: {
        currentRevenue: 100000,
        projectedRevenue: 115000,
        revenueChange: 15000,
        revenueChangePercent: 15
      },
      profitabilityImpact: {
        currentProfit: 30000,
        projectedProfit: 36000,
        profitChange: 6000,
        profitChangePercent: 20,
        marginImpact: 2.5
      },
      operationalImpact: {
        inventoryTurnover: 1.2,
        cashFlowImprovement: 10000,
        operationalEfficiency: 15
      },
      riskAssessment: {
        riskLevel: 'medium' as const,
        keyRisks: ['Market risk'],
        mitigationStrategies: ['Monitor market']
      },
      timeframe: {
        shortTerm: 'Quick wins',
        mediumTerm: 'Sustained growth',
        longTerm: 'Market leadership'
      },
      recommendations: ['Start implementation'],
      confidence: 85
    },
    comparativeScenarios: [],
    executiveSummary: 'Test summary'
  })),
  dynamicDescriptionFlow: vi.fn(() => Promise.resolve({
    optimizedProducts: [
      {
        sku: 'TEST-001',
        originalTitle: 'Test Product',
        optimizedTitle: 'Premium Test Product',
        originalDescription: 'Basic description',
        optimizedDescription: 'Enhanced description',
        keyFeatures: ['Feature 1'],
        seoKeywords: ['test', 'product'],
        emotionalTriggers: ['Premium'],
        uniqueSellingPoints: ['High quality'],
        callToAction: 'Buy now',
        improvementScore: 85,
        targetAudienceMatch: 90
      }
    ],
    overallStrategy: 'Test strategy',
    performanceProjections: {
      estimatedConversionImprovement: 25,
      seoImpact: 'Improved rankings',
      brandConsistency: 90
    },
    implementationTips: ['Test tip'],
    abTestRecommendations: ['Test A/B']
  }))
}));

describe('API Routes Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Advanced Analytics API (/api/analytics/advanced)', () => {
    it('should handle ABC analysis requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=abc-analysis');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
      expect(data.metadata).toBeDefined();
      expect(data.metadata.analysisType).toBe('abc-analysis');
      expect(data.metadata.companyId).toBe('test-company-123');
    });

    it('should handle demand forecast requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=demand-forecast');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
      
      if (data.data.length > 0) {
        const forecast = data.data[0];
        expect(forecast).toHaveProperty('sku');
        expect(forecast).toHaveProperty('forecasted_demand');
        expect(forecast).toHaveProperty('confidence');
      }
    });

    it('should handle sales velocity requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=sales-velocity');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle gross margin analysis requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=gross-margin');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle hidden opportunities requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=hidden-opportunities');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle supplier performance requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=supplier-performance');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle inventory turnover requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=inventory-turnover');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle customer insights requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=customer-insights');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should handle channel fees requests', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=channel-fees');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data)).toBe(true);
    });

    it('should return 400 for missing type parameter', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Analysis type is required');
    });

    it('should return 400 for invalid type parameter', async () => {
      const request = createRequest('http://localhost/api/analytics/advanced?type=invalid-type');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Unknown analysis type');
    });
  });

  describe('AI Analytics API (/api/ai-analytics)', () => {
    it('should handle bundle suggestions GET requests', async () => {
      const request = createRequest('http://localhost/api/ai-analytics?type=bundle-suggestions&count=3');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.data.suggestions).toBeDefined();
      expect(Array.isArray(data.data.suggestions)).toBe(true);
      expect(data.data.totalPotentialRevenue).toBeDefined();
      expect(typeof data.data.totalPotentialRevenue).toBe('number');
    });

    it('should handle economic impact GET requests', async () => {
      const request = createRequest('http://localhost/api/ai-analytics?type=economic-impact&scenario=pricing_optimization&priceChange=10');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.data.analysis).toBeDefined();
      expect(data.data.analysis.revenueImpact).toBeDefined();
      expect(data.data.analysis.profitabilityImpact).toBeDefined();
    });

    it('should handle dynamic descriptions GET requests', async () => {
      const request = createRequest('http://localhost/api/ai-analytics?type=dynamic-descriptions&optimization=conversion&audience=general');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.data.optimizedProducts).toBeDefined();
      expect(Array.isArray(data.data.optimizedProducts)).toBe(true);
    });

    it('should handle summary format requests', async () => {
      const request = createRequest('http://localhost/api/ai-analytics?type=bundle-suggestions&format=summary');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.type).toBe('bundle-suggestions');
      expect(data.timestamp).toBeDefined();
      expect(data.companyId).toBe('test-company-123');
      expect(data.bundleCount).toBeDefined();
      expect(data.totalPotentialRevenue).toBeDefined();
    });

    it('should handle POST requests for bundle analysis', async () => {
      const requestBody = {
        analysisType: 'bundle-suggestions',
        parameters: {
          count: 5
        }
      };

      const request = createRequest('http://localhost/api/ai-analytics', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      const response = await AIAnalyticsPOST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.metadata.analysisType).toBe('bundle-suggestions');
      expect(data.metadata.parameters).toEqual(requestBody.parameters);
    });

    it('should handle POST requests for economic impact analysis', async () => {
      const requestBody = {
        analysisType: 'economic-impact',
        parameters: {
          scenarioType: 'pricing_optimization',
          priceChangePercent: 15
        }
      };

      const request = createRequest('http://localhost/api/ai-analytics', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      const response = await AIAnalyticsPOST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.metadata.analysisType).toBe('economic-impact');
    });

    it('should handle batch analysis POST requests', async () => {
      const requestBody = {
        analysisType: 'batch-analysis',
        parameters: {
          bundleCount: 3,
          economicScenario: 'inventory_reduction',
          economicParameters: {
            inventoryReductionPercent: 20
          }
        }
      };

      const request = createRequest('http://localhost/api/ai-analytics', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
      });

      const response = await AIAnalyticsPOST(request);
      const data = await response.json();

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.data.bundleAnalysis).toBeDefined();
      expect(data.data.economicAnalysis).toBeDefined();
      expect(data.data.combinedInsights).toBeDefined();
      expect(data.data.combinedInsights.totalRevenueOpportunity).toBeDefined();
    });

    it('should return 400 for missing analysis type in POST', async () => {
      const request = createRequest('http://localhost/api/ai-analytics', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
      });

      const response = await AIAnalyticsPOST(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Analysis type is required');
    });

    it('should return 400 for economic impact without scenario type', async () => {
      const request = createRequest('http://localhost/api/ai-analytics?type=economic-impact');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(400);
      expect(data.error).toContain('Scenario type is required');
    });
  });

  describe('Error Handling', () => {
    it('should handle authentication errors', async () => {
      // Mock auth failure
      vi.mocked(require('@/lib/auth-helpers').requireUser)
        .mockRejectedValue(new Error('Authentication failed'));

      const request = createRequest('http://localhost/api/analytics/advanced?type=abc-analysis');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toBeDefined();
    });

    it('should handle database errors gracefully', async () => {
      // Mock database error
      vi.mocked(require('@/services/database').getAbcAnalysisFromDB)
        .mockRejectedValue(new Error('Database connection failed'));

      const request = createRequest('http://localhost/api/analytics/advanced?type=abc-analysis');
      const response = await GET(request);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toBeDefined();
    });

    it('should handle AI flow errors', async () => {
      // Mock AI flow error
      vi.mocked(require('@/ai/flows').suggestBundlesFlow)
        .mockRejectedValue(new Error('AI service unavailable'));

      const request = createRequest('http://localhost/api/ai-analytics?type=bundle-suggestions');
      const response = await AIAnalyticsGET(request);
      const data = await response.json();

      expect(response.status).toBe(500);
      expect(data.error).toBeDefined();
    });
  });

  describe('Performance Tests', () => {
    it('should respond within reasonable time for simple analytics', async () => {
      const startTime = Date.now();
      const request = createRequest('http://localhost/api/analytics/advanced?type=abc-analysis');
      await GET(request);
      const duration = Date.now() - startTime;

      // Should complete within 5 seconds
      expect(duration).toBeLessThan(5000);
    });

    it('should respond within reasonable time for AI analytics', async () => {
      const startTime = Date.now();
      const request = createRequest('http://localhost/api/ai-analytics?type=bundle-suggestions');
      await AIAnalyticsGET(request);
      const duration = Date.now() - startTime;

      // Should complete within 10 seconds (AI processing takes longer)
      expect(duration).toBeLessThan(10000);
    });
  });
});
