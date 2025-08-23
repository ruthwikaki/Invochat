import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as database from '@/services/database';

// Mock dependencies
vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    defineFlow: vi.fn().mockImplementation((_config, handler) => handler),
    defineTool: vi.fn().mockImplementation((_config, handler) => handler),
    definePrompt: vi.fn().mockImplementation((config) => config),
  },
}));
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: {
    ai: {
      model: 'mock-model'
    }
  }
}));

// Import the actual functions to test
import { suggestBundlesFlow, getBundleSuggestions } from '@/ai/flows/suggest-bundles-flow';

const mockGetUnifiedInventoryFromDB = vi.mocked(database.getUnifiedInventoryFromDB);

describe('Suggest Bundles Flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.MOCK_AI = 'true';
  });

  describe('suggestBundlesFlow', () => {
    it('should generate bundle suggestions with mock data', async () => {
      const testCompanyId = 'test-company-id';
      // Keep MOCK_AI = 'true' for this test since we want to test the mock functionality
      
      const result = await suggestBundlesFlow({ companyId: testCompanyId, count: 3 });

      expect(result).toEqual({
        suggestions: expect.arrayContaining([
          expect.objectContaining({
            bundleName: expect.any(String),
            productSkus: expect.any(Array),
            reasoning: expect.any(String),
            potentialBenefit: expect.any(String),
            suggestedPrice: expect.any(Number),
            estimatedDemand: expect.any(Number),
            profitMargin: expect.any(Number),
            seasonalFactors: expect.any(Array),
            targetCustomerSegment: expect.any(String),
            crossSellOpportunity: expect.any(Number),
          }),
        ]),
        analysis: expect.any(String),
        totalPotentialRevenue: expect.any(Number),
        implementationRecommendations: expect.any(Array),
      });

      // When MOCK_AI is true, database functions are not called
      expect(mockGetUnifiedInventoryFromDB).not.toHaveBeenCalled();
    });

    it('should handle insufficient products', async () => {
      const testCompanyId = 'test-company-id';
      // Disable MOCK_AI for this test to test actual logic
      process.env.MOCK_AI = 'false';
      
      const mockInventory = {
        items: [
          {
            sku: 'PROD-001',
            product_title: 'Only Product',
            product_type: 'electronics',
            price: 2999,
          },
        ],
        totalCount: 1,
      } as any;

      mockGetUnifiedInventoryFromDB.mockResolvedValue(mockInventory);

      const result = await suggestBundlesFlow({ companyId: testCompanyId, count: 3 });

      expect(result).toEqual({
        suggestions: [],
        analysis: 'Not enough product data is available to generate bundle suggestions. Please import more products.',
        totalPotentialRevenue: 0,
        implementationRecommendations: [],
      });
      
      // Restore MOCK_AI for other tests
      process.env.MOCK_AI = 'true';
    });

    it('should handle database errors gracefully', async () => {
      const testCompanyId = 'test-company-id';
      // Disable MOCK_AI for this test to test actual error handling
      process.env.MOCK_AI = 'false';
      
      mockGetUnifiedInventoryFromDB.mockRejectedValue(new Error('Database error'));

      await expect(suggestBundlesFlow({ companyId: testCompanyId, count: 3 })).rejects.toThrow('An error occurred while generating bundle suggestions.');
      
      // Restore MOCK_AI for other tests
      process.env.MOCK_AI = 'true';
    });
  });

  describe('getBundleSuggestions tool', () => {
    it('should be properly configured as an AI tool', () => {
      expect(getBundleSuggestions).toBeDefined();
      expect(typeof getBundleSuggestions).toBe('function');
    });

    it('should call the flow with correct parameters', async () => {
      const testInput = { companyId: 'test-company-id', count: 5 };
      const mockInventory = {
        items: [
          {
            sku: 'PROD-001',
            product_title: 'Premium Widget',
            product_type: 'electronics',
            price: 2999,
          },
          {
            sku: 'PROD-002',
            product_title: 'Standard Component',
            product_type: 'electronics',
            price: 1599,
          },
        ],
        totalCount: 2,
      } as any;

      mockGetUnifiedInventoryFromDB.mockResolvedValue(mockInventory);

      const result = await getBundleSuggestions(testInput);

      expect(result).toEqual(expect.objectContaining({
        suggestions: expect.any(Array),
        analysis: expect.any(String),
      }));
    });
  });
});
