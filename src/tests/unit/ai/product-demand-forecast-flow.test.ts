import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

// Partially mock lib/utils to mock one function but keep others
vi.mock('@/lib/utils', async (importOriginal) => {
    const actual = await importOriginal<typeof import('@/lib/utils')>();
    return {
        ...actual, // Keep original implementations for other functions
        linearRegression: vi.fn(() => ({ slope: 5, intercept: 100 })),
    };
});

import * as database from '@/services/database';

describe('Product Demand Forecast Flow', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it('should forecast demand for a product with sufficient sales data', async () => {
    vi.doMock('@/ai/genkit', () => ({
        ai: {
            definePrompt: vi.fn().mockReturnValue(
                vi.fn().mockResolvedValue({
                    output: {
                        confidence: 'High',
                        analysis: "Mock demand forecast insights",
                        trend: 'Upward'
                    }
                })
            ),
            defineFlow: vi.fn((_config, implementation) => implementation),
        }
    }));
    
    const mockSalesData = Array.from({ length: 10 }, (_, i) => ({ sale_date: `2024-01-${String(i+1).padStart(2,'0')}`, total_quantity: 100 + i }));
    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData);
    
    const { productDemandForecastFlow } = await import('@/ai/flows/product-demand-forecast-flow');
    const { linearRegression } = await import('@/lib/utils');

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
    expect(linearRegression).toHaveBeenCalled();
    expect(result.confidence).toBe('High');
    expect(result.analysis).toBe('Mock demand forecast insights');
  });

  it('should return a low confidence forecast for insufficient data', async () => {
     vi.doMock('@/ai/genkit', () => ({
        ai: {
            defineFlow: vi.fn((_config, implementation) => implementation),
        }
    }));

    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue([]);
    const { productDemandForecastFlow } = await import('@/ai/flows/product-demand-forecast-flow');
    const { linearRegression } = await import('@/lib/utils');

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(result.confidence).toBe('Low');
    expect(result.analysis).toContain('not enough historical sales data');
    expect(linearRegression).not.toHaveBeenCalled();
  });
});
