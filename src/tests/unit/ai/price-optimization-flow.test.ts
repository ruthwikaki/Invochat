import { describe, it, expect, vi, beforeEach } from 'vitest';
import { priceOptimizationFlow, getPriceOptimizationSuggestions } from '@/ai/flows/price-optimization-flow';
import * as database from '@/services/database';
import { ai } from '@/ai/genkit';

vi.mock('@/ai/genkit', () => {
  return {
    ai: {
      defineTool: vi.fn((config, implementation) => {
        const mockTool = vi.fn(implementation || (() => Promise.resolve({})));
        mockTool.config = config;
        return mockTool;
      }),
      defineFlow: vi.fn((config, implementation) => {
        const mockFlow = vi.fn(implementation || (() => Promise.resolve({})));
        mockFlow.config = config;
        return mockFlow;
      }),
      definePrompt: vi.fn((config) => {
        const mockPrompt = vi.fn(async () => ({ 
          output: {
            suggestions: [
                {
                  sku: 'SKU001',
                  productName: 'Fast Mover',
                  currentPrice: 1000,
                  suggestedPrice: 1100,
                  reasoning: 'High demand, potential for margin increase',
                  estimatedImpact: 'Increased profit per unit',
                },
            ],
            analysis: "Mock price optimization analysis"
          }
        }));
        mockPrompt.config = config;
        return mockPrompt;
      }),
    },
  };
});
vi.mock('@/services/database');


const mockInventory = {
  items: [
    { sku: 'SKU001', product_title: 'Fast Mover', cost: 500, price: 1000, inventory_quantity: 20 },
    { sku: 'SKU002', product_title: 'Slow Mover', cost: 2000, price: 2500, inventory_quantity: 100 },
  ],
  totalCount: 2,
};

describe('Price Optimization Flow', () => {

  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should fetch inventory and generate price suggestions', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue(mockInventory as any);
    (database.getHistoricalSalesForSkus as vi.Mock).mockResolvedValue([]);

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);

    expect(database.getUnifiedInventoryFromDB).toHaveBeenCalledWith(input.companyId, { limit: 50 });
    expect(ai.definePrompt).toHaveBeenCalled();
    expect(result.suggestions).toHaveLength(1);
    expect(result.suggestions[0].suggestedPrice).toBe(1100);
  });

  it('should handle no inventory data', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue({ items: [], totalCount: 0 });

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);
    expect(result.analysis).toContain('Not enough product data');
    expect(ai.definePrompt).not.toHaveBeenCalled();
  });
});
