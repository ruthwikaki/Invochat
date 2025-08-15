
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';

vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));
vi.mock('@/ai/genkit', () => {
  return {
    ai: {
      definePrompt: vi.fn(() => vi.fn()),
      defineFlow: vi.fn((_config, implementation) => implementation),
      defineTool: vi.fn((_config, implementation) => implementation),
    },
  };
});


import * as database from '@/services/database';
import { priceOptimizationFlow } from '@/ai/flows/price-optimization-flow';
import { ai } from '@/ai/genkit';


describe('Price Optimization Flow', () => {
  let mockPromptFn: Mock;

  beforeEach(() => {
    vi.clearAllMocks();
    mockPromptFn = (ai.definePrompt as Mock).mock.results[0].value;
  });

  it('should fetch inventory and generate price suggestions', async () => {
    mockPromptFn.mockResolvedValue({
        output: {
            suggestions: [{ sku: 'TEST-001', currentPrice: 1000, suggestedPrice: 1200, productName: 'Test', reasoning: 'test', estimatedImpact: 'test' }],
            analysis: "Mock price optimization analysis"
        }
    });
    
    const mockInventory = { items: [{ id: 'variant-id-1', sku: 'TEST-001', product_title: 'Test', cost: 500, price: 1000, inventory_quantity: 10, product_id: 'prod-id-1' }], totalCount: 1 };
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue(mockInventory);
    (database.getHistoricalSalesForSkus as vi.Mock).mockResolvedValue([]);
    
    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);

    expect(database.getUnifiedInventoryFromDB).toHaveBeenCalledWith(input.companyId, { limit: 50 });
    expect(result.suggestions).toHaveLength(1);
    expect(result.analysis).toBe('Mock price optimization analysis');
    expect(mockPromptFn).toHaveBeenCalled();
  });

  it('should handle no inventory data', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue({ items: [], totalCount: 0 });

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);
    
    expect(result.analysis).toContain('Not enough product data');
  });
});
