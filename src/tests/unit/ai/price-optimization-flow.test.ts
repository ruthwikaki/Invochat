
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock dependencies first
vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

vi.mock('@/ai/genkit', () => {
  const mockPromptFunction = vi.fn();
  
  return {
    ai: {
      definePrompt: vi.fn(() => mockPromptFunction),
      defineFlow: vi.fn((config, implementation) => implementation),
      defineTool: vi.fn((config, implementation) => implementation),
    },
  };
});

import { priceOptimizationFlow } from '@/ai/flows/price-optimization-flow';
import * as database from '@/services/database';
import { ai } from '@/ai/genkit';

describe('Price Optimization Flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    
    const mockPrompt = (ai.definePrompt as any)();
    mockPrompt.mockResolvedValue({
      output: {
        suggestions: [{ sku: 'TEST-001', currentPrice: 1000, suggestedPrice: 1200, cost: 500 }],
        analysis: "Mock price optimization analysis"
      }
    });
     (database.getHistoricalSalesForSkus as vi.Mock).mockResolvedValue([]);
  });

  it('should fetch inventory and generate price suggestions', async () => {
    const mockInventory = {
        items: [
            { sku: 'TEST-001', product_title: 'Test', cost: 500, price: 1000, inventory_quantity: 10 },
        ],
        totalCount: 1,
    };
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue(mockInventory);

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);

    expect(database.getUnifiedInventoryFromDB).toHaveBeenCalledWith(input.companyId, { limit: 50 });
    expect(result.suggestions).toHaveLength(1);
  });

  it('should handle no inventory data', async () => {
    (database.getUnifiedInventoryFromDB as vi.Mock).mockResolvedValue({ items: [], totalCount: 0 });

    const input = { companyId: 'test-company-id' };
    const result = await priceOptimizationFlow(input);
    
    expect(result.analysis).toContain('Not enough product data');
  });
});
