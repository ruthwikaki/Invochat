import { describe, it, expect, beforeEach, vi } from 'vitest';
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

// Mock Supabase client
vi.mock('@/lib/supabase', () => ({
  createClient: vi.fn(() => ({
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          order: vi.fn(() => ({
            limit: vi.fn(() => Promise.resolve({
              data: [
                {
                  sku: 'TEST-001',
                  product_name: 'Test Product',
                  total_revenue: 10000,
                  total_quantity: 100,
                  velocity_score: 8.5,
                  category: 'A',
                  gross_margin_percentage: 35.5,
                  profit: 3550,
                  opportunity_score: 75
                }
              ],
              error: null
            }))
          }))
        }))
      }))
    }))
  }))
}));

describe('Advanced Analytics Functions', () => {
  const mockCompanyId = 'test-company-123';

  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('ABC Analysis', () => {
    it('should categorize products by revenue contribution', async () => {
      const result = await getAbcAnalysisFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const item = result![0];
        expect(item).toHaveProperty('sku');
        expect(item).toHaveProperty('product_name');
        expect(item).toHaveProperty('total_revenue');
        expect(item).toHaveProperty('category');
        expect(['A', 'B', 'C']).toContain(item.category);
      }
    });

    it('should handle empty product data gracefully', async () => {
      // Override mock to return empty data
      vi.mocked(require('@/lib/supabase').createClient).mockReturnValue({
        from: () => ({
          select: () => ({
            eq: () => ({
              order: () => ({
                limit: () => Promise.resolve({ data: [], error: null })
              })
            })
          })
        })
      });

      const result = await getAbcAnalysisFromDB(mockCompanyId);
      expect(result).toEqual([]);
    });
  });

  describe('Demand Forecasting', () => {
    it('should generate demand forecasts with moving averages', async () => {
      const result = await getDemandForecastFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const forecast = result![0];
        expect(forecast).toHaveProperty('sku');
        expect(forecast).toHaveProperty('product_name');
        expect(forecast).toHaveProperty('forecasted_demand');
        expect(forecast).toHaveProperty('confidence');
        expect(forecast).toHaveProperty('trend');
        
        // Validate forecast values are reasonable
        expect(forecast.forecasted_demand).toBeGreaterThanOrEqual(0);
        expect(forecast.confidence).toBeGreaterThanOrEqual(0);
        expect(forecast.confidence).toBeLessThanOrEqual(100);
      }
    });

    it('should calculate trend direction correctly', async () => {
      const result = await getDemandForecastFromDB(mockCompanyId);
      
      if (result && result.length > 0) {
        const forecast = result![0];
        expect(forecast).toHaveProperty('trend');
        expect(['increasing', 'decreasing', 'stable']).toContain(forecast.trend);
      }
    });
  });

  describe('Sales Velocity Analysis', () => {
    it('should calculate sales velocity metrics', async () => {
      const result = await getSalesVelocityFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const velocity = result![0];
        expect(velocity).toHaveProperty('sku');
        expect(velocity).toHaveProperty('product_name');
        expect(velocity).toHaveProperty('daily_velocity');
        expect(velocity).toHaveProperty('velocity_score');
        expect(velocity).toHaveProperty('trend');
        
        // Velocity score should be between 0-10
        expect(velocity.velocity_score).toBeGreaterThanOrEqual(0);
        expect(velocity.velocity_score).toBeLessThanOrEqual(10);
        
        // Units per day should be non-negative
        expect(velocity.daily_velocity).toBeGreaterThanOrEqual(0);
      }
    });

    it('should identify velocity trends', async () => {
      const result = await getSalesVelocityFromDB(mockCompanyId);
      
      if (result && result.length > 0) {
        const velocity = result![0];
        expect(['accelerating', 'stable', 'declining']).toContain(velocity.trend);
      }
    });
  });

  describe('Gross Margin Analysis', () => {
    it('should calculate comprehensive margin metrics', async () => {
      const result = await getGrossMarginAnalysisFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const margin = result![0];
        expect(margin).toHaveProperty('sku');
        expect(margin).toHaveProperty('product_name');
        expect(margin).toHaveProperty('gross_margin_percentage');
        expect(margin).toHaveProperty('revenue');
        expect(margin).toHaveProperty('cost');
        expect(margin).toHaveProperty('profit');
        expect(margin).toHaveProperty('margin_per_unit');
        
        // Margin percentage should be reasonable
        expect(margin.gross_margin_percentage).toBeGreaterThanOrEqual(0);
        expect(margin.gross_margin_percentage).toBeLessThanOrEqual(100);
        
        // Revenue should be greater than cost for positive margin
        if (margin.gross_margin_percentage > 0) {
          expect(margin.revenue).toBeGreaterThan(margin.cost);
          expect(margin.profit).toBeGreaterThan(0);
        }
      }
    });
  });

  describe('Hidden Revenue Opportunities', () => {
    it('should identify optimization opportunities', async () => {
      const result = await getHiddenRevenueOpportunitiesFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const opportunity = result![0];
        expect(opportunity).toHaveProperty('sku');
        expect(opportunity).toHaveProperty('product_name');
        expect(opportunity).toHaveProperty('opportunity_type');
        expect(opportunity).toHaveProperty('opportunity_score');
        expect(opportunity).toHaveProperty('potential_revenue_increase');
        expect(opportunity).toHaveProperty('recommendation');
        
        // Opportunity score should be 0-100
        expect(opportunity.opportunity_score).toBeGreaterThanOrEqual(0);
        expect(opportunity.opportunity_score).toBeLessThanOrEqual(100);
        
        // Valid opportunity types
        const validTypes = [
          'price_optimization',
          'inventory_optimization', 
          'cross_sell_opportunity',
          'bundle_opportunity',
          'reorder_optimization'
        ];
        expect(validTypes).toContain(opportunity.opportunity_type);
      }
    });
  });

  describe('Supplier Performance Scoring', () => {
    it('should calculate supplier performance metrics', async () => {
      const result = await getSupplierPerformanceScoreFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const supplier = result![0];
        expect(supplier).toHaveProperty('supplier_name');
        expect(supplier).toHaveProperty('overall_score');
        expect(supplier).toHaveProperty('stock_performance_score');
        expect(supplier).toHaveProperty('cost_performance_score');
        expect(supplier).toHaveProperty('reliability_score');
        expect(supplier).toHaveProperty('performance_grade');
        
        // All ratings should be 0-10
        expect(supplier.overall_score).toBeGreaterThanOrEqual(0);
        expect(supplier.overall_score).toBeLessThanOrEqual(10);
        expect(supplier.stock_performance_score).toBeGreaterThanOrEqual(0);
        expect(supplier.stock_performance_score).toBeLessThanOrEqual(10);
        
        // Performance grade should be valid
        expect(['A', 'B', 'C', 'D', 'F']).toContain(supplier.performance_grade);
      }
    });
  });

  describe('Inventory Turnover Analysis', () => {
    it('should calculate turnover metrics', async () => {
      const result = await getInventoryTurnoverAnalysisFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const turnover = result![0];
        expect(turnover).toHaveProperty('sku');
        expect(turnover).toHaveProperty('product_name');
        expect(turnover).toHaveProperty('turnover_ratio');
        expect(turnover).toHaveProperty('days_of_inventory');
        expect(turnover).toHaveProperty('performance_rating');
        expect(turnover).toHaveProperty('recommendation');
        
        // Turnover ratio should be positive
        expect(turnover.turnover_ratio).toBeGreaterThanOrEqual(0);
        
        // Days of inventory should be positive
        expect(turnover.days_sales_in_inventory).toBeGreaterThanOrEqual(0);
        
        // Performance rating should be valid
        expect(['Excellent', 'Good', 'Fair', 'Poor']).toContain(turnover.performance_rating);
      }
    });
  });

  describe('Customer Behavior Insights', () => {
    it('should analyze customer segments', async () => {
      const result = await getCustomerBehaviorInsightsFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const insight = result![0];
        expect(insight).toHaveProperty('segment');
        expect(insight).toHaveProperty('total_orders');
        expect(insight).toHaveProperty('average_order_value');
        expect(insight).toHaveProperty('purchase_frequency_per_month');
        expect(insight).toHaveProperty('preferred_category');
        expect(insight).toHaveProperty('customer_lifetime_value');
        
        // Total orders should be positive
        expect(insight.total_orders).toBeGreaterThanOrEqual(0);
        
        // AOV should be positive
        expect(insight.average_order_value).toBeGreaterThanOrEqual(0);
        
        // Purchase frequency should be reasonable
        expect(insight.purchase_frequency_per_month).toBeGreaterThanOrEqual(0);
        
        // Segment should be valid
        expect(['high_value', 'regular', 'at_risk', 'new_customer']).toContain(insight.segment);
      }
    });
  });

  describe('Multi-Channel Fee Analysis', () => {
    it('should analyze channel profitability', async () => {
      const result = await getMultiChannelFeeAnalysisFromDB(mockCompanyId);
      
      expect(result).toBeDefined();
      expect(Array.isArray(result)).toBe(true);
      
      if (result && result.length > 0) {
        const channel = result![0];
        expect(channel).toHaveProperty('channel_name');
        expect(channel).toHaveProperty('total_sales');
        expect(channel).toHaveProperty('total_fees');
        expect(channel).toHaveProperty('fee_percentage');
        expect(channel).toHaveProperty('net_profit');
        expect(channel).toHaveProperty('profit_margin');
        expect(channel).toHaveProperty('recommendation');
        
        // Sales should be positive
        expect(channel.total_sales).toBeGreaterThanOrEqual(0);
        
        // Fee percentage should be 0-100%
        expect(channel.fee_percentage).toBeGreaterThanOrEqual(0);
        expect(channel.fee_percentage).toBeLessThanOrEqual(100);
        
        // Profit margin should be reasonable (-100% to 100%)
        expect(channel.profit_margin).toBeGreaterThanOrEqual(-100);
        expect(channel.profit_margin).toBeLessThanOrEqual(100);
      }
    });
  });

  describe('Error Handling', () => {
    it('should handle database errors gracefully', async () => {
      // Mock database error
      vi.mocked(require('@/lib/supabase').createClient).mockReturnValue({
        from: () => ({
          select: () => ({
            eq: () => ({
              order: () => ({
                limit: () => Promise.resolve({ 
                  data: null, 
                  error: { message: 'Database connection failed' }
                })
              })
            })
          })
        })
      });

      await expect(getAbcAnalysisFromDB(mockCompanyId)).rejects.toThrow();
    });

    it('should validate company ID parameter', async () => {
      await expect(getAbcAnalysisFromDB('')).rejects.toThrow();
      await expect(getAbcAnalysisFromDB(null as any)).rejects.toThrow();
    });
  });

  describe('Performance Tests', () => {
    it('should complete analysis within reasonable time', async () => {
      const startTime = Date.now();
      await getAbcAnalysisFromDB(mockCompanyId);
      const duration = Date.now() - startTime;
      
      // Should complete within 5 seconds
      expect(duration).toBeLessThan(5000);
    });

    it('should handle large datasets efficiently', async () => {
      // Mock large dataset
      const largeDataset = Array.from({ length: 1000 }, (_, i) => ({
        sku: `TEST-${i.toString().padStart(3, '0')}`,
        product_name: `Test Product ${i}`,
        total_revenue: Math.random() * 10000,
        total_quantity: Math.floor(Math.random() * 1000),
        velocity_score: Math.random() * 10,
        category: 'A',
        gross_margin_percentage: Math.random() * 50,
        profit: Math.random() * 5000,
        opportunity_score: Math.random() * 100
      }));

      vi.mocked(require('@/lib/supabase').createClient).mockReturnValue({
        from: () => ({
          select: () => ({
            eq: () => ({
              order: () => ({
                limit: () => Promise.resolve({ data: largeDataset, error: null })
              })
            })
          })
        })
      });

      const startTime = Date.now();
      const result = await getAbcAnalysisFromDB(mockCompanyId);
      const duration = Date.now() - startTime;
      
      expect(result).toBeDefined();
      expect(result!.length).toBe(1000);
      expect(duration).toBeLessThan(10000); // Should complete within 10 seconds
    });
  });
});
