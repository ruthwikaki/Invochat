
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Mock } from 'vitest';

vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

// Partially mock lib/utils to mock one function but keep others
vi.mock('@/lib/utils', async (importOriginal) => {
    const actual = await importOriginal<typeof import('@/lib/utils')>();
    return {
        ...actual,
        linearRegression: vi.fn(() => ({ slope: 5, intercept: 100 })),
    };
});

// Since date-fns is used by the flow, it needs to be available.
// We can let the original implementation pass through.
vi.mock('date-fns', async (importOriginal) => {
  return await importOriginal<typeof import('date-fns')>();
});


import * as database from '@/services/database';
import { linearRegression } from '@/lib/utils';

describe('Product Demand Forecast Flow', () => {

  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
  });

  it('should forecast demand for a product with sufficient sales data', async () => {
    const mockPromptFn = vi.fn().mockResolvedValue({
      output: {
          confidence: 'High' as const,
          analysis: "Mock demand forecast insights",
          trend: 'Upward' as const
      }
    });

    vi.doMock('@/ai/genkit', () => ({
      ai: {
        definePrompt: vi.fn().mockReturnValue(mockPromptFn),
        defineFlow: vi.fn((_config, implementation) => implementation),
        defineTool: vi.fn((_config, implementation) => implementation),
      }
    }));
    
    const mockSalesData = Array.from({ length: 10 }, (_, i) => ({ 
      sale_date: new Date(2024, 0, i + 1).toISOString(),
      total_quantity: 100 + i 
    }));
    
    (database.getHistoricalSalesForSingleSkuFromDB as Mock)
      .mockResolvedValue(mockSalesData);
    
    const { productDemandForecastFlow } = await import('@/ai/flows/product-demand-forecast-flow');

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
    expect(linearRegression).toHaveBeenCalled();
    expect(result.confidence).toBe('High');
    expect(result.analysis).toBe('Mock demand forecast insights');
    expect(result.trend).toBe('Upward');
  });

  it('should return a low confidence forecast for insufficient data', async () => {
    vi.doMock('@/ai/genkit', () => ({
      ai: {
        defineFlow: vi.fn((_config, implementation) => implementation),
        defineTool: vi.fn(),
        definePrompt: vi.fn(),
      }
    }));

    (database.getHistoricalSalesForSingleSkuFromDB as Mock).mockResolvedValue([]);

    const { productDemandForecastFlow } = await import('@/ai/flows/product-demand-forecast-flow');

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(result.confidence).toBe('Low');
    expect(result.analysis).toContain('not enough historical sales data');
    expect(linearRegression).not.toHaveBeenCalled();
  });
});
