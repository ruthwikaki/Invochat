
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { suggestPriceOptimizationsFlow } from '@/ai/flows/price-optimization-flow';
import * as database from '@/services/database';
import * as genkit from '@/ai/genkit';

vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: vi.fn(() => vi.fn()),
    defineFlow: vi.fn((config, func) => func),
  },
}));

const mockInventory = {
  items: [
    { sku: 'SKU001', product_title: 'Fast Mover', cost: 500, price: 1000, inventory_quantity: 20 },
    { sku: 'SKU002', product_title: 'Slow Mover', cost: 2000, price: 2500, inventory_quantity: 100 },
  ],
  totalCount: 2,
};

const mockAiResponse = {
  suggestions: [
    {
      sku: 'SKU001',
      productName: 'Fast Mover',
      currentPrice: 1000,
      suggestedPrice: 1100, // Increase price
      reasoning: 'High demand, potential for margin increase',
      estimatedImpact: 'Increased profit per unit',
    },
     {
      sku: 'SKU002',
      productName: 'Slow Mover',
      currentPrice: 2500,
      suggestedPrice: 2250, // Decrease price
      reasoning: 'Slow sales, consider a promotional price',
      estimatedImpact: 'Higher sales volume, improved cash flow',
    },
  ],
  analysis: 'Identified one candidate for a price increase and one for a promotional decrease.',
};

describe('Price Optimization Flow', () => {
  let suggestPricesPrompt: any;

  beforeEach(() => {
    vi.resetAllMocks();
    suggestPricesPrompt = vi.fn().mockResolvedValue({ output: mockAiResponse });
    vi.spyOn(genkit.ai, 'definePrompt').mockReturnValue(suggestPricesPrompt);
  });

  it('should fetch inventory and generate price suggestions', async () => {
    vi.spyOn(database, 'getUnifiedInventoryFromDB').mockResolvedValue(mockInventory as any);
    
    const input = { companyId: 'test-company-id' };
    const result = await suggestPriceOptimizationsFlow(input);

    expect(database.getUnifiedInventoryFromDB).toHaveBeenCalledWith(input.companyId, { limit: 50 });
    expect(suggestPricesPrompt).toHaveBeenCalledWith({
      products: [
        { sku: 'SKU001', name: 'Fast Mover', cost: 500, price: 1000, quantity: 20 },
        { sku: 'SKU002', name: 'Slow Mover', cost: 2000, price: 2500, quantity: 100 },
      ],
    });
    expect(result.suggestions).toHaveLength(2);
    expect(result.suggestions[0].suggestedPrice).toBe(1100);
    expect(result.suggestions[1].suggestedPrice).toBe(2250);
  });

  it('should handle no inventory data', async () => {
    vi.spyOn(database, 'getUnifiedInventoryFromDB').mockResolvedValue({ items: [], totalCount: 0 });

    const input = { companyId: 'test-company-id' };
    const result = await suggestPriceOptimizationsFlow(input);
    expect(result.analysis).toContain('Not enough product data');
    expect(suggestPricesPrompt).not.toHaveBeenCalled();
  });
});
