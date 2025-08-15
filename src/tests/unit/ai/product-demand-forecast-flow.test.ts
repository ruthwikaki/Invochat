
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

// Partially mock lib/utils to mock one function but keep others
vi.mock('@/lib/utils', async (importOriginal) => {
    const actual = await importOriginal<typeof import('@/lib/utils')>();
    return {
        ...actual,
        linearRegression: vi.fn(() => ({ slope: 5, intercept: 100 })),
    };
});

import * as database from '@/services/database';
import { productDemandForecastFlow } from '@/ai/flows/product-demand-forecast-flow';
import { linearRegression } from '@/lib/utils';
import { ai } from '@/ai/genkit';


describe('Product Demand Forecast Flow', () => {
  let mockPromptFn: Mock;

  beforeEach(() => {
    vi.clearAllMocks();
    mockPromptFn = (ai.definePrompt as Mock).mock.results[0].value;
  });

  it('should forecast demand for a product with sufficient sales data', async () => {
    mockPromptFn.mockResolvedValue({
      output: {
          confidence: 'High',
          analysis: "Mock demand forecast insights",
          trend: 'Upward'
      }
    });
    
    const mockSalesData = Array.from({ length: 10 }, (_, i) => ({ 
      sale_date: `2024-01-${String(i+1).padStart(2,'0')}`, 
      total_quantity: 100 + i 
    }));
    
    (database.getHistoricalSalesForSingleSkuFromDB as Mock)
      .mockResolvedValue(mockSalesData);

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
    expect(linearRegression).toHaveBeenCalled();
    expect(result.confidence).toBe('High');
    expect(result.analysis).toBe('Mock demand forecast insights');
    expect(result.trend).toBe('Upward');
    expect(mockPromptFn).toHaveBeenCalled();
  });

  it('should return a low confidence forecast for insufficient data', async () => {
    (database.getHistoricalSalesForSingleSkuFromDB as Mock)
      .mockResolvedValue([]);
    const { linearRegression: lrMock } = await import('@/lib/utils');


    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(result.confidence).toBe('Low');
    expect(result.analysis).toContain('not enough historical sales data');
    expect(lrMock).not.toHaveBeenCalled();
  });
});
