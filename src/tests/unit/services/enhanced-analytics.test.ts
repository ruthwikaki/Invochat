import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as database from '@/services/database';

// Mock dependencies
vi.mock('@/services/database');

const mockGetHiddenRevenueOpportunitiesFromDB = vi.mocked(database.getHiddenRevenueOpportunitiesFromDB);
const mockGetSupplierPerformanceScoreFromDB = vi.mocked(database.getSupplierPerformanceScoreFromDB);
const mockGetInventoryTurnoverAnalysisFromDB = vi.mocked(database.getInventoryTurnoverAnalysisFromDB);
const mockGetCustomerBehaviorInsightsFromDB = vi.mocked(database.getCustomerBehaviorInsightsFromDB);
const mockGetMultiChannelFeeAnalysisFromDB = vi.mocked(database.getMultiChannelFeeAnalysisFromDB);

describe('Enhanced Analytics Functions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('getHiddenRevenueOpportunitiesFromDB', () => {
    it('should return hidden revenue opportunities', async () => {
      const mockOpportunities = [
        {
          sku: 'PROD-001',
          product_name: 'High Margin Product',
          opportunity_type: 'High-Margin Underperformer',
          priority: 'Critical',
          current_performance: {
            daily_velocity: 0.5,
            margin_percentage: 65,
            monthly_revenue: 2500,
            revenue_rank: 'Bottom 50%',
          },
          opportunity_metrics: {
            potential_daily_velocity: 2.0,
            target_margin: 65,
            monthly_revenue_lift: 15000,
            annual_revenue_potential: 180000,
            confidence_score: 0.75,
          },
          ai_insights: {
            primary_issue: 'Visibility & Discovery Problem',
            demand_signal: 'Growing demand detected',
            competitive_advantage: 'Excellent 65% margin provides pricing flexibility',
            market_opportunity: 'Untapped market potential',
          },
          recommended_actions: [
            {
              action: 'Launch visibility campaign',
              impact: 'High',
              timeline: '2-4 weeks',
              investment: 'Medium marketing spend',
              expected_lift: '150-300%',
            },
          ],
          financial_impact: {
            investment_needed: 500,
            roi_estimate: 8.5,
            payback_period_months: 2.5,
            risk_level: 'Low',
          },
          opportunity_score: 85.5,
        },
      ];

      mockGetHiddenRevenueOpportunitiesFromDB.mockResolvedValue(mockOpportunities);

      const result = await database.getHiddenRevenueOpportunitiesFromDB('test-company-id');

      expect(result).toEqual(mockOpportunities);
      expect(mockGetHiddenRevenueOpportunitiesFromDB).toHaveBeenCalledWith('test-company-id');
    });

    it('should handle empty opportunities', async () => {
      mockGetHiddenRevenueOpportunitiesFromDB.mockResolvedValue([]);

      const result = await database.getHiddenRevenueOpportunitiesFromDB('test-company-id');

      expect(result).toEqual([]);
    });

    it('should handle database errors', async () => {
      mockGetHiddenRevenueOpportunitiesFromDB.mockRejectedValue(new Error('Database connection failed'));

      await expect(database.getHiddenRevenueOpportunitiesFromDB('test-company-id')).rejects.toThrow('Database connection failed');
    });
  });

  describe('getSupplierPerformanceScoreFromDB', () => {
    it('should return supplier performance scores', async () => {
      const mockScores = [
        {
          supplier_id: 'supplier-1',
          supplier_name: 'Premium Supplier',
          contact_email: 'contact@supplier.com',
          total_products: 25,
          low_stock_products: 2,
          average_cost: 125.50,
          stock_performance_score: 92.5,
          cost_performance_score: 88.0,
          reliability_score: 95.0,
          overall_score: 91.8,
          performance_grade: 'A',
          recommendation: 'Expand product line with this supplier',
        },
      ];

      mockGetSupplierPerformanceScoreFromDB.mockResolvedValue(mockScores as any);

      const result = await database.getSupplierPerformanceScoreFromDB('test-company-id');

      expect(result).toEqual(mockScores);
      expect(mockGetSupplierPerformanceScoreFromDB).toHaveBeenCalledWith('test-company-id');
    });
  });

  describe('getInventoryTurnoverAnalysisFromDB', () => {
    it('should return inventory turnover analysis', async () => {
      const mockAnalysis = [
        {
          sku: 'PROD-001',
          product_name: 'Fast Moving Product',
          current_inventory: 100,
          units_sold: 850,
          inventory_value: 5000,
          cogs: 3500,
          turnover_ratio: 8.5,
          days_sales_in_inventory: 43,
          performance_rating: 'Excellent',
          recommendation: 'Maintain current inventory levels',
        },
      ];

      mockGetInventoryTurnoverAnalysisFromDB.mockResolvedValue(mockAnalysis as any);

      const result = await database.getInventoryTurnoverAnalysisFromDB('test-company-id', 365);

      expect(result).toEqual(mockAnalysis);
      expect(mockGetInventoryTurnoverAnalysisFromDB).toHaveBeenCalledWith('test-company-id', 365);
    });

    it('should use default days parameter', async () => {
      const mockAnalysis: any[] = [];
      mockGetInventoryTurnoverAnalysisFromDB.mockResolvedValue(mockAnalysis);

      await database.getInventoryTurnoverAnalysisFromDB('test-company-id');

      expect(mockGetInventoryTurnoverAnalysisFromDB).toHaveBeenCalledWith('test-company-id');
    });
  });

  describe('getCustomerBehaviorInsightsFromDB', () => {
    it('should return customer behavior insights', async () => {
      const mockInsights = [
        {
          customer_id: 'cust-001',
          customer_name: 'Premium Customer',
          email: 'customer@example.com',
          segment: 'High Value',
          total_orders: 25,
          total_spent: 5250.75,
          average_order_value: 210.03,
          purchase_frequency_per_month: 3.2,
          days_since_first_order: 365,
          preferred_category: 'Electronics',
          customer_lifetime_value: 8500.50,
          recommendation: 'Offer loyalty program benefits',
        },
      ];

      mockGetCustomerBehaviorInsightsFromDB.mockResolvedValue(mockInsights as any);

      const result = await database.getCustomerBehaviorInsightsFromDB('test-company-id');

      expect(result).toEqual(mockInsights);
      expect(mockGetCustomerBehaviorInsightsFromDB).toHaveBeenCalledWith('test-company-id');
    });
  });

  describe('getMultiChannelFeeAnalysisFromDB', () => {
    it('should return multi-channel fee analysis', async () => {
      const mockAnalysis = {
        total_fees_paid: 15750.25,
        fee_breakdown_by_channel: [
          {
            channel: 'Amazon',
            total_fees: 8200.50,
            fee_percentage: 12.5,
            transaction_volume: 65000,
            profitability_after_fees: 52799.50,
          },
          {
            channel: 'Shopify',
            total_fees: 4350.75,
            fee_percentage: 2.9,
            transaction_volume: 150000,
            profitability_after_fees: 145649.25,
          },
        ],
        optimization_opportunities: [
          {
            channel: 'Amazon',
            suggestion: 'Negotiate volume discount',
            potential_savings: 820.05,
            implementation_effort: 'Medium',
          },
        ],
        comparative_analysis: {
          most_profitable_channel: 'Shopify',
          highest_fee_channel: 'Amazon',
          recommendations: ['diversify away from high-fee channels'],
        },
      };

      mockGetMultiChannelFeeAnalysisFromDB.mockResolvedValue(mockAnalysis as any);

      const result = await database.getMultiChannelFeeAnalysisFromDB('test-company-id');

      expect(result).toEqual(mockAnalysis);
      expect(mockGetMultiChannelFeeAnalysisFromDB).toHaveBeenCalledWith('test-company-id');
    });
  });

  describe('Advanced Analytics Integration', () => {
    it('should work together for comprehensive analysis', async () => {
      // Mock data for multiple analytics functions
      const mockOpportunities = [{ sku: 'PROD-001', opportunity_type: 'High-Margin Underperformer' }];
      const mockSupplierScores = [{
        supplier_id: 'supplier-1',
        supplier_name: 'Test Supplier',
        contact_email: 'test@supplier.com',
        total_products: 10,
        low_stock_products: 1,
        average_cost: 85.0,
        stock_performance_score: 85,
        cost_performance_score: 80,
        reliability_score: 90,
        overall_score: 85,
        performance_grade: 'B',
        recommendation: 'Good performance'
      }];
      const mockTurnoverAnalysis = [{
        sku: 'PROD-001',
        product_name: 'Test Product',
        current_inventory: 50,
        units_sold: 325,
        inventory_value: 2500,
        cogs: 1750,
        turnover_ratio: 6.5,
        days_sales_in_inventory: 56,
        performance_rating: 'Good',
        recommendation: 'Monitor closely'
      }];

      mockGetHiddenRevenueOpportunitiesFromDB.mockResolvedValue(mockOpportunities as any);
      mockGetSupplierPerformanceScoreFromDB.mockResolvedValue(mockSupplierScores as any);
      mockGetInventoryTurnoverAnalysisFromDB.mockResolvedValue(mockTurnoverAnalysis as any);

      const companyId = 'test-company-id';

      // Execute multiple analytics functions
      const [opportunities, supplierScores, turnoverAnalysis] = await Promise.all([
        database.getHiddenRevenueOpportunitiesFromDB(companyId),
        database.getSupplierPerformanceScoreFromDB(companyId),
        database.getInventoryTurnoverAnalysisFromDB(companyId, 365),
      ]);

      expect(opportunities).toEqual(mockOpportunities);
      expect(supplierScores).toEqual(mockSupplierScores);
      expect(turnoverAnalysis).toEqual(mockTurnoverAnalysis);

      // Verify all functions were called with correct parameters
      expect(mockGetHiddenRevenueOpportunitiesFromDB).toHaveBeenCalledWith(companyId);
      expect(mockGetSupplierPerformanceScoreFromDB).toHaveBeenCalledWith(companyId);
      expect(mockGetInventoryTurnoverAnalysisFromDB).toHaveBeenCalledWith(companyId, 365);
    });
  });
});
