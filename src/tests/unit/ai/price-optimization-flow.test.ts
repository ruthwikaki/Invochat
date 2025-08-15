import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock dependencies first
vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

const mockPromptFunction = vi.fn();

vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: vi.fn(() => mockPromptFunction),
    defineFlow: vi.fn((config, implementation) => implementation),
    defineTool: vi.fn((config, implementation) => implementation),
  },
}));

import { priceOptimizationFlow } from '@/ai/flows/price-optimization-flow';
import * as database from '@/services/database';

const mockInventory = {
  items: [
    { sku: 'SKU001', product_title: 'Fast Mover', cost: 500, price: 1000, inventory_quantity: 20 },
    { sku: 'SKU002', product_title: 'Slow Mover', cost: 2000, price: 2500, inventory_quantity: 100 },
  ],
  totalCount: 2,
};

describe('Price Optimization Flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    
    mockPromptFunction.mockResolvedValue({
      output: {
        suggestions: [{ sku: 'TEST-001', currentPrice: 1000, suggestedPrice: 1200, cost: 500 }],
        analysis: "Mock price optimization analysis"
      }
    });
     (database.getHistoricalSalesForSkus as vi.Mock).mockResolvedValue([]);
  });

  it('should fetch inventory and generate price suggestions', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue(mockInventory);

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);

    expect(database.getUnifiedInventoryFromDB).toHaveBeenCalledWith(input.companyId, { limit: 50 });
    expect(result.suggestions).toHaveLength(1);
    expect(result.suggestions[0].sku).toBe('TEST-001');
  });

  it('should handle no inventory data', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue({ items: [], totalCount: 0 });

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);
    
    expect(result.analysis).toContain('Not enough product data');
  });
});
