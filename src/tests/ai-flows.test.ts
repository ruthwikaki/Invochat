import { describe, it, expect, beforeEach, vi } from 'vitest';
import { suggestBundlesFlow } from '@/ai/flows/suggest-bundles-flow';
import { economicImpactFlow } from '@/ai/flows/economic-impact-flow';
import { dynamicDescriptionFlow } from '@/ai/flows/dynamic-descriptions-flow';

// Mock the database service
vi.mock('@/services/database', () => ({
  getUnifiedInventoryFromDB: vi.fn(() => Promise.resolve({
    items: [
      {
        sku: 'TEST-001',
        product_title: 'Test Product 1',
        price: 2999, // $29.99 in cents
        product_type: 'Electronics',
        inventory_quantity: 100,
        body_html: 'Original description for test product 1'
      },
      {
        sku: 'TEST-002', 
        product_title: 'Test Product 2',
        price: 4999, // $49.99 in cents
        product_type: 'Electronics',
        inventory_quantity: 50,
        body_html: 'Original description for test product 2'
      }
    ],
    totalCount: 2
  })),
  getGrossMarginAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product 1',
      gross_margin_percentage: 35.5,
      revenue: 2999,
      cost: 1934,
      profit: 1065,
      quantity_sold: 100,
      margin_per_unit: 10.65
    }
  ])),
  getInventoryTurnoverAnalysisFromDB: vi.fn(() => Promise.resolve([
    {
      sku: 'TEST-001',
      product_name: 'Test Product 1',
      turnover_ratio: 4.2,
      performance_rating: 'Good'
    }
  ]))
}));

// Mock the logger
vi.mock('@/lib/logger', () => ({
  logger: {
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn()
  }
}));

// Mock the config
vi.mock('@/config/app-config', () => ({
  config: {
    ai: {
      model: 'test-model'
    }
  }
}));

describe('AI Flow Tests', () => {
  const mockCompanyId = 'test-company-123';

  beforeEach(() => {
    vi.clearAllMocks();
    // Set mock mode for all tests
    process.env.MOCK_AI = 'true';
  });

  describe('Bundle Suggestions Flow', () => {
    it('should generate bundle suggestions successfully', async () => {
      const result = await suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 3
      });

      expect(result).toBeDefined();
      expect(result.suggestions).toBeDefined();
      expect(Array.isArray(result.suggestions)).toBe(true);
      expect(result.suggestions.length).toBeLessThanOrEqual(3);
      expect(result.analysis).toBeDefined();
      expect(typeof result.analysis).toBe('string');
      expect(result.totalPotentialRevenue).toBeDefined();
      expect(typeof result.totalPotentialRevenue).toBe('number');
      expect(result.implementationRecommendations).toBeDefined();
      expect(Array.isArray(result.implementationRecommendations)).toBe(true);

      // Validate bundle suggestion structure
      if (result.suggestions.length > 0) {
        const bundle = result.suggestions[0];
        expect(bundle).toHaveProperty('bundleName');
        expect(bundle).toHaveProperty('productSkus');
        expect(bundle).toHaveProperty('reasoning');
        expect(bundle).toHaveProperty('potentialBenefit');
        expect(bundle).toHaveProperty('suggestedPrice');
        expect(bundle).toHaveProperty('estimatedDemand');
        expect(bundle).toHaveProperty('profitMargin');
        expect(bundle).toHaveProperty('seasonalFactors');
        expect(bundle).toHaveProperty('targetCustomerSegment');
        expect(bundle).toHaveProperty('crossSellOpportunity');

        // Validate data types and ranges
        expect(typeof bundle.bundleName).toBe('string');
        expect(Array.isArray(bundle.productSkus)).toBe(true);
        expect(typeof bundle.reasoning).toBe('string');
        expect(typeof bundle.suggestedPrice).toBe('number');
        expect(bundle.suggestedPrice).toBeGreaterThan(0);
        expect(typeof bundle.estimatedDemand).toBe('number');
        expect(bundle.estimatedDemand).toBeGreaterThanOrEqual(0);
        expect(typeof bundle.profitMargin).toBe('number');
        expect(bundle.profitMargin).toBeGreaterThanOrEqual(0);
        expect(Array.isArray(bundle.seasonalFactors)).toBe(true);
        expect(typeof bundle.targetCustomerSegment).toBe('string');
        expect(typeof bundle.crossSellOpportunity).toBe('number');
        expect(bundle.crossSellOpportunity).toBeGreaterThanOrEqual(0);
      }
    });

    it('should handle custom bundle count', async () => {
      const result = await suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 1
      });

      expect(result.suggestions.length).toBeLessThanOrEqual(1);
    });

    it('should validate required parameters', async () => {
      await expect(suggestBundlesFlow({
        companyId: '',
        count: 3
      })).rejects.toThrow();
    });
  });

  describe('Economic Impact Flow', () => {
    it('should analyze pricing optimization scenario', async () => {
      const result = await economicImpactFlow({
        companyId: mockCompanyId,
        scenarioType: 'pricing_optimization',
        parameters: {
          priceChangePercent: 10
        }
      });

      expect(result).toBeDefined();
      expect(result.analysis).toBeDefined();
      expect(result.comparativeScenarios).toBeDefined();
      expect(result.executiveSummary).toBeDefined();

      // Validate analysis structure
      const analysis = result.analysis;
      expect(analysis).toHaveProperty('scenario');
      expect(analysis).toHaveProperty('revenueImpact');
      expect(analysis).toHaveProperty('profitabilityImpact');
      expect(analysis).toHaveProperty('operationalImpact');
      expect(analysis).toHaveProperty('riskAssessment');
      expect(analysis).toHaveProperty('timeframe');
      expect(analysis).toHaveProperty('recommendations');
      expect(analysis).toHaveProperty('confidence');

      // Validate revenue impact
      const revenueImpact = analysis.revenueImpact;
      expect(revenueImpact).toHaveProperty('currentRevenue');
      expect(revenueImpact).toHaveProperty('projectedRevenue');
      expect(revenueImpact).toHaveProperty('revenueChange');
      expect(revenueImpact).toHaveProperty('revenueChangePercent');
      expect(typeof revenueImpact.currentRevenue).toBe('number');
      expect(typeof revenueImpact.projectedRevenue).toBe('number');
      expect(typeof revenueImpact.revenueChange).toBe('number');
      expect(typeof revenueImpact.revenueChangePercent).toBe('number');

      // Validate profitability impact
      const profitabilityImpact = analysis.profitabilityImpact;
      expect(profitabilityImpact).toHaveProperty('currentProfit');
      expect(profitabilityImpact).toHaveProperty('projectedProfit');
      expect(profitabilityImpact).toHaveProperty('profitChange');
      expect(profitabilityImpact).toHaveProperty('profitChangePercent');
      expect(profitabilityImpact).toHaveProperty('marginImpact');

      // Validate risk assessment
      const riskAssessment = analysis.riskAssessment;
      expect(riskAssessment).toHaveProperty('riskLevel');
      expect(riskAssessment).toHaveProperty('keyRisks');
      expect(riskAssessment).toHaveProperty('mitigationStrategies');
      expect(['low', 'medium', 'high']).toContain(riskAssessment.riskLevel);
      expect(Array.isArray(riskAssessment.keyRisks)).toBe(true);
      expect(Array.isArray(riskAssessment.mitigationStrategies)).toBe(true);

      // Validate confidence score
      expect(analysis.confidence).toBeGreaterThanOrEqual(0);
      expect(analysis.confidence).toBeLessThanOrEqual(100);

      // Validate comparative scenarios
      expect(Array.isArray(result.comparativeScenarios)).toBe(true);
      if (result.comparativeScenarios.length > 0) {
        const scenario = result.comparativeScenarios[0];
        expect(scenario).toHaveProperty('name');
        expect(scenario).toHaveProperty('revenueImpact');
        expect(scenario).toHaveProperty('profitImpact');
        expect(scenario).toHaveProperty('riskLevel');
      }
    });

    it('should handle different scenario types', async () => {
      const scenarioTypes = [
        'inventory_reduction',
        'new_product_launch',
        'market_expansion',
        'cost_reduction'
      ] as const;

      for (const scenarioType of scenarioTypes) {
        const result = await economicImpactFlow({
          companyId: mockCompanyId,
          scenarioType,
          parameters: {}
        });

        expect(result).toBeDefined();
        expect(result.analysis.scenario).toContain(scenarioType.replace('_', ' '));
      }
    });

    it('should validate scenario parameters', async () => {
      await expect(economicImpactFlow({
        companyId: mockCompanyId,
        scenarioType: 'pricing_optimization' as any,
        parameters: {}
      })).resolves.toBeDefined();
    });
  });

  describe('Dynamic Description Flow', () => {
    it('should optimize product descriptions', async () => {
      const result = await dynamicDescriptionFlow({
        companyId: mockCompanyId,
        optimizationType: 'conversion',
        targetAudience: 'general',
        tone: 'professional',
        maxLength: 300
      });

      expect(result).toBeDefined();
      expect(result.optimizedProducts).toBeDefined();
      expect(result.overallStrategy).toBeDefined();
      expect(result.performanceProjections).toBeDefined();
      expect(result.implementationTips).toBeDefined();
      expect(result.abTestRecommendations).toBeDefined();

      // Validate optimized products structure
      expect(Array.isArray(result.optimizedProducts)).toBe(true);
      if (result.optimizedProducts.length > 0) {
        const product = result.optimizedProducts[0];
        expect(product).toHaveProperty('sku');
        expect(product).toHaveProperty('originalTitle');
        expect(product).toHaveProperty('optimizedTitle');
        expect(product).toHaveProperty('originalDescription');
        expect(product).toHaveProperty('optimizedDescription');
        expect(product).toHaveProperty('keyFeatures');
        expect(product).toHaveProperty('seoKeywords');
        expect(product).toHaveProperty('emotionalTriggers');
        expect(product).toHaveProperty('uniqueSellingPoints');
        expect(product).toHaveProperty('callToAction');
        expect(product).toHaveProperty('improvementScore');
        expect(product).toHaveProperty('targetAudienceMatch');

        // Validate data types and ranges
        expect(typeof product.sku).toBe('string');
        expect(typeof product.originalTitle).toBe('string');
        expect(typeof product.optimizedTitle).toBe('string');
        expect(typeof product.optimizedDescription).toBe('string');
        expect(Array.isArray(product.keyFeatures)).toBe(true);
        expect(Array.isArray(product.seoKeywords)).toBe(true);
        expect(Array.isArray(product.emotionalTriggers)).toBe(true);
        expect(Array.isArray(product.uniqueSellingPoints)).toBe(true);
        expect(typeof product.callToAction).toBe('string');
        expect(typeof product.improvementScore).toBe('number');
        expect(product.improvementScore).toBeGreaterThanOrEqual(0);
        expect(product.improvementScore).toBeLessThanOrEqual(100);
        expect(typeof product.targetAudienceMatch).toBe('number');
        expect(product.targetAudienceMatch).toBeGreaterThanOrEqual(0);
        expect(product.targetAudienceMatch).toBeLessThanOrEqual(100);

        // Validate description length
        expect(product.optimizedDescription.length).toBeLessThanOrEqual(300);
      }

      // Validate performance projections
      const projections = result.performanceProjections;
      expect(projections).toHaveProperty('estimatedConversionImprovement');
      expect(projections).toHaveProperty('seoImpact');
      expect(projections).toHaveProperty('brandConsistency');
      expect(typeof projections.estimatedConversionImprovement).toBe('number');
      expect(typeof projections.seoImpact).toBe('string');
      expect(typeof projections.brandConsistency).toBe('number');
      expect(projections.brandConsistency).toBeGreaterThanOrEqual(0);
      expect(projections.brandConsistency).toBeLessThanOrEqual(100);

      // Validate recommendations
      expect(Array.isArray(result.implementationTips)).toBe(true);
      expect(Array.isArray(result.abTestRecommendations)).toBe(true);
    });

    it('should handle different optimization types', async () => {
      const optimizationTypes = [
        'seo',
        'conversion', 
        'brand',
        'technical',
        'emotional'
      ] as const;

      for (const optimizationType of optimizationTypes) {
        const result = await dynamicDescriptionFlow({
          companyId: mockCompanyId,
          optimizationType,
          targetAudience: 'general',
          tone: 'professional',
          maxLength: 250
        });

        expect(result).toBeDefined();
        expect(result.overallStrategy).toContain(optimizationType);
      }
    });

    it('should handle different target audiences', async () => {
      const audiences = [
        'general',
        'technical',
        'luxury',
        'budget',
        'business'
      ] as const;

      for (const audience of audiences) {
        const result = await dynamicDescriptionFlow({
          companyId: mockCompanyId,
          optimizationType: 'conversion',
          targetAudience: audience,
          tone: 'professional',
          maxLength: 300
        });

        expect(result).toBeDefined();
        expect(result.overallStrategy).toContain(audience);
      }
    });

    it('should handle specific product optimization', async () => {
      const result = await dynamicDescriptionFlow({
        companyId: mockCompanyId,
        productSku: 'TEST-001',
        optimizationType: 'conversion',
        targetAudience: 'general',
        tone: 'professional',
        maxLength: 300
      });

      expect(result).toBeDefined();
      expect(result.optimizedProducts.length).toBeGreaterThan(0);
    });

    it('should respect max length constraints', async () => {
      const maxLength = 150;
      const result = await dynamicDescriptionFlow({
        companyId: mockCompanyId,
        optimizationType: 'conversion',
        targetAudience: 'general',
        tone: 'professional',
        maxLength
      });

      if (result.optimizedProducts.length > 0) {
        const product = result.optimizedProducts[0];
        expect(product.optimizedDescription.length).toBeLessThanOrEqual(maxLength);
      }
    });
  });

  describe('Error Handling', () => {
    beforeEach(() => {
      // Disable mock mode to test real AI calls and error handling
      delete process.env.MOCK_AI;
    });

    it('should handle invalid company IDs', async () => {
      await expect(suggestBundlesFlow({
        companyId: '',
        count: 3
      })).rejects.toThrow();
    });

    it('should handle network errors gracefully', async () => {
      // Mock network failure
      vi.mocked(require('@/services/database').getUnifiedInventoryFromDB)
        .mockRejectedValue(new Error('Network error'));

      await expect(suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 3
      })).rejects.toThrow('Network error');
    });

    it('should handle empty product data', async () => {
      // Mock empty data
      vi.mocked(require('@/services/database').getUnifiedInventoryFromDB)
        .mockResolvedValue({ items: [], totalCount: 0 });

      await expect(suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 3
      })).rejects.toThrow();
    });
  });

  describe('Performance Tests', () => {
    it('should complete bundle analysis within reasonable time', async () => {
      const startTime = Date.now();
      await suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 5
      });
      const duration = Date.now() - startTime;
      
      // Should complete within 10 seconds (accounting for AI processing)
      expect(duration).toBeLessThan(10000);
    });

    it('should handle large bundle counts efficiently', async () => {
      const startTime = Date.now();
      await suggestBundlesFlow({
        companyId: mockCompanyId,
        count: 10
      });
      const duration = Date.now() - startTime;
      
      // Should still complete within reasonable time
      expect(duration).toBeLessThan(15000);
    });
  });
});
