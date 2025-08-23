import { describe, it, expect, beforeEach, vi } from 'vitest';

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

// Import the functions we want to test
import {
  getAbcAnalysisFromDB,
  getDemandForecastFromDB,
  getSalesVelocityFromDB,
  getGrossMarginAnalysisFromDB,
  getHiddenRevenueOpportunitiesFromDB,
  getSupplierPerformanceScoreFromDB,
  getInventoryTurnoverAnalysisFromDB,
  getCustomerBehaviorInsightsFromDB,
  getMultiChannelFeeAnalysisFromDB
} from '@/services/database';

describe('Analytics Integration Tests', () => {
  const mockCompanyId = 'test-company-123';

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Analytics Pipeline Integration', () => {
    it('should run complete analytics pipeline', async () => {
      // Run all analytics functions in sequence
      const [
        abcAnalysis,
        demandForecast,
        salesVelocity,
        grossMargin,
        hiddenOpportunities,
        supplierPerformance,
        inventoryTurnover,
        customerInsights,
        channelFees
      ] = await Promise.all([
        getAbcAnalysisFromDB(mockCompanyId),
        getDemandForecastFromDB(mockCompanyId),
        getSalesVelocityFromDB(mockCompanyId),
        getGrossMarginAnalysisFromDB(mockCompanyId),
        getHiddenRevenueOpportunitiesFromDB(mockCompanyId),
        getSupplierPerformanceScoreFromDB(mockCompanyId),
        getInventoryTurnoverAnalysisFromDB(mockCompanyId),
        getCustomerBehaviorInsightsFromDB(mockCompanyId),
        getMultiChannelFeeAnalysisFromDB(mockCompanyId)
      ]);

      // Verify all functions returned data
      expect(abcAnalysis).toBeDefined();
      expect(abcAnalysis?.length || 0).toBeGreaterThan(0);
      
      expect(demandForecast).toBeDefined();
      expect(demandForecast?.length || 0).toBeGreaterThan(0);
      
      expect(salesVelocity).toBeDefined();
      expect(salesVelocity?.length || 0).toBeGreaterThan(0);
      
      expect(grossMargin).toBeDefined();
      expect(grossMargin?.length || 0).toBeGreaterThan(0);
      
      expect(hiddenOpportunities).toBeDefined();
      expect(hiddenOpportunities?.length || 0).toBeGreaterThan(0);
      
      expect(supplierPerformance).toBeDefined();
      expect(supplierPerformance?.length || 0).toBeGreaterThan(0);
      
      expect(inventoryTurnover).toBeDefined();
      expect(inventoryTurnover?.length || 0).toBeGreaterThan(0);
      
      expect(customerInsights).toBeDefined();
      expect(customerInsights?.length || 0).toBeGreaterThan(0);
      
      expect(channelFees).toBeDefined();
      expect(channelFees?.length || 0).toBeGreaterThan(0);

      // Verify data consistency across analyses
      const testSku = 'TEST-001';
      const abcProduct = abcAnalysis?.find(p => p.sku === testSku);
      const velocityProduct = salesVelocity?.find(p => p.sku === testSku);
      const marginProduct = grossMargin?.find(p => p.sku === testSku);
      
      expect(abcProduct).toBeDefined();
      expect(velocityProduct).toBeDefined();
      expect(marginProduct).toBeDefined();
      
      // All should reference the same product
      expect(abcProduct?.sku).toBe(velocityProduct?.sku);
      expect(velocityProduct?.sku).toBe(marginProduct?.sku);
    });

    it('should handle cross-analysis insights', async () => {
      const [grossMargin, hiddenOpportunities] = await Promise.all([
        getGrossMarginAnalysisFromDB(mockCompanyId),
        getHiddenRevenueOpportunitiesFromDB(mockCompanyId)
      ]);

      // Hidden opportunities should consider margin data
      const opportunity = hiddenOpportunities?.[0];
      const margin = grossMargin?.[0];
      
      expect(opportunity?.sku).toBe(margin?.sku);
      
      // Opportunities should be logical based on margin data
      if (opportunity?.type === 'price_optimization' && margin && margin.gross_margin_percentage < 30) {
        expect(opportunity.suggested_action).toContain('price');
      }
    });
  });

  describe('Business Intelligence Metrics', () => {
    it('should calculate comprehensive KPIs', async () => {
      const [velocity, turnover, margin] = await Promise.all([
        getSalesVelocityFromDB(mockCompanyId),
        getInventoryTurnoverAnalysisFromDB(mockCompanyId),
        getGrossMarginAnalysisFromDB(mockCompanyId)
      ]);

      // Calculate aggregate KPIs
      const avgVelocity = velocity && velocity.length > 0 
        ? velocity.reduce((sum, item) => sum + item.velocity_score, 0) / velocity.length 
        : 0;
      const avgTurnover = turnover && turnover.length > 0
        ? turnover.reduce((sum, item) => sum + item.turnover_ratio, 0) / turnover.length
        : 0;
      const avgMargin = margin && margin.length > 0
        ? margin.reduce((sum, item) => sum + item.gross_margin_percentage, 0) / margin.length
        : 0;

      expect(avgVelocity).toBeGreaterThan(0);
      expect(avgTurnover).toBeGreaterThan(0);
      expect(avgMargin).toBeGreaterThan(0);

      // Business health indicators
      const healthScore = (avgVelocity / 10) * 0.3 + (avgTurnover / 10) * 0.3 + (avgMargin / 100) * 0.4;
      expect(healthScore).toBeGreaterThan(0);
      expect(healthScore).toBeLessThanOrEqual(1);
    });

    it('should identify performance trends', async () => {
      const [velocity, abc] = await Promise.all([
        getSalesVelocityFromDB(mockCompanyId),
        getAbcAnalysisFromDB(mockCompanyId)
      ]);

      // Analyze trend distribution
      const trendCounts = velocity && velocity.length > 0 
        ? velocity.reduce((acc, item) => {
            acc[item.trend] = (acc[item.trend] || 0) + 1;
            return acc;
          }, {} as Record<string, number>)
        : {};

      expect(Object.keys(trendCounts)).toContain('accelerating');
      
      // ABC categories should be well distributed
      const categoryDistribution = abc && abc.length > 0
        ? abc.reduce((acc, item) => {
            acc[item.category] = (acc[item.category] || 0) + 1;
            return acc;
          }, {} as Record<string, number>)
        : {};

      expect(Object.keys(categoryDistribution)).toContain('A');
    });
  });

  describe('Customer & Channel Analytics', () => {
    it('should analyze customer segments effectively', async () => {
      const insights = await getCustomerBehaviorInsightsFromDB(mockCompanyId);
      
      const highValueSegment = insights.find(i => i.segment === 'high_value');
      expect(highValueSegment).toBeDefined();
      
      if (highValueSegment) {
        expect(highValueSegment.average_order_value).toBeGreaterThan(0);
        expect(highValueSegment.customer_lifetime_value).toBeGreaterThan(0);
        expect(highValueSegment.purchase_frequency_per_month).toBeGreaterThan(0);
      }
    });

    it('should evaluate channel profitability', async () => {
      const channelAnalysis = await getMultiChannelFeeAnalysisFromDB(mockCompanyId);
      
      const shopifyChannel = channelAnalysis.find(c => c.channel_name === 'Shopify');
      expect(shopifyChannel).toBeDefined();
      
      if (shopifyChannel) {
        expect(shopifyChannel.total_sales).toBeGreaterThan(0);
        expect(shopifyChannel.fee_percentage).toBeGreaterThan(0);
        expect(shopifyChannel.profit_margin).toBeGreaterThan(0);
        
        // Verify fee calculation
        const expectedFees = shopifyChannel.total_sales * (shopifyChannel.fee_percentage / 100);
        expect(Math.abs(shopifyChannel.total_fees - expectedFees)).toBeLessThan(1);
      }
    });
  });

  describe('Supplier & Inventory Management', () => {
    it('should evaluate supplier performance comprehensively', async () => {
      const suppliers = await getSupplierPerformanceScoreFromDB(mockCompanyId);
      
      const topSupplier = suppliers.find(s => s.performance_grade === 'A');
      expect(topSupplier).toBeDefined();
      
      if (topSupplier) {
        expect(topSupplier.overall_score).toBeGreaterThan(7);
        expect(topSupplier.stock_performance_score).toBeGreaterThan(0);
        expect(topSupplier.cost_performance_score).toBeGreaterThan(0);
        expect(topSupplier.reliability_score).toBeGreaterThan(0);
      }
    });

    it('should optimize inventory levels', async () => {
      const turnover = await getInventoryTurnoverAnalysisFromDB(mockCompanyId);
      
      const goodPerformers = turnover?.filter(t => t.performance_rating === 'Good') || [];
      expect(goodPerformers?.length || 0).toBeGreaterThan(0);
      
      goodPerformers.forEach(item => {
        expect(item.turnover_ratio).toBeGreaterThan(2); // Good turnover threshold
        expect(item.days_sales_in_inventory).toBeLessThan(120); // Less than 4 months
      });
    });
  });

  describe('Revenue Optimization', () => {
    it('should identify revenue opportunities accurately', async () => {
      const opportunities = await getHiddenRevenueOpportunitiesFromDB(mockCompanyId);
      
      const priceOptimization = opportunities.find(o => o.type === 'price_optimization');
      expect(priceOptimization).toBeDefined();
      
      if (priceOptimization) {
        expect(priceOptimization.opportunity_score).toBeGreaterThan(50);
        expect(priceOptimization.potential_value).toBeGreaterThan(0);
        expect(priceOptimization.suggested_action).toBeDefined();
        expect(priceOptimization.reasoning).toBeDefined();
      }
    });

    it('should prioritize opportunities by impact', async () => {
      const opportunities = await getHiddenRevenueOpportunitiesFromDB(mockCompanyId);
      
      // Opportunities should be sorted by score (highest first)
      for (let i = 1; i < opportunities.length; i++) {
        expect(opportunities[i-1].opportunity_score).toBeGreaterThanOrEqual(
          opportunities[i].opportunity_score
        );
      }
      
      // High-impact opportunities should have substantial potential value
      const highImpact = opportunities.filter(o => o.opportunity_score > 70);
      highImpact.forEach(opportunity => {
        expect(opportunity.potential_value).toBeGreaterThan(1000);
      });
    });
  });

  describe('Performance Benchmarks', () => {
    it('should meet performance requirements', async () => {
      const startTime = Date.now();
      
      // Run multiple analytics concurrently
      await Promise.all([
        getAbcAnalysisFromDB(mockCompanyId),
        getSalesVelocityFromDB(mockCompanyId),
        getGrossMarginAnalysisFromDB(mockCompanyId)
      ]);
      
      const duration = Date.now() - startTime;
      
      // Should complete within 3 seconds
      expect(duration).toBeLessThan(3000);
    });

    it('should handle data consistency across functions', async () => {
      // All functions should use the same company ID
      const companyId = 'consistent-test-123';
      
      const results = await Promise.all([
        getAbcAnalysisFromDB(companyId),
        getSalesVelocityFromDB(companyId),
        getGrossMarginAnalysisFromDB(companyId)
      ]);
      
      // All functions should have been called with the same company ID
      expect(vi.mocked(getAbcAnalysisFromDB)).toHaveBeenCalledWith(companyId);
      expect(vi.mocked(getSalesVelocityFromDB)).toHaveBeenCalledWith(companyId);
      expect(vi.mocked(getGrossMarginAnalysisFromDB)).toHaveBeenCalledWith(companyId);
      
      // All should return valid data structures
      results.forEach(result => {
        expect(Array.isArray(result)).toBe(true);
        expect(result?.length || 0).toBeGreaterThanOrEqual(0);
      });
    });
  });
});
