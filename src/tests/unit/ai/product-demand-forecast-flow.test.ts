import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/lib/utils', () => ({
  linearRegression: vi.fn(() => ({ slope: 5, intercept: 100 })),
  differenceInDays: vi.fn(() => 1), // Mock this utility
}));
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

import { productDemandForecastFlow } from '@/ai/flows/product-demand-forecast-flow';
import * as database from '@/services/database';
import * as utils from '@/lib/utils';
import { ai } from '@/ai/genkit';

describe('Product Demand Forecast Flow', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    
    mockPromptFunction.mockResolvedValue({
      output: {
        confidence: 'High',
        analysis: "Mock demand forecast insights",
        trend: 'Upward'
      }
    });
  });

  it('should forecast demand for a product with sufficient sales data', async () => {
    const mockSalesData = [
      { sale_date: '2024-01-01', total_quantity: 100 },
      { sale_date: '2024-02-01', total_quantity: 110 },
      { sale_date: '2024-03-01', total_quantity: 120 },
      { sale_date: '2024-04-01', total_quantity: 130 },
      { sale_date: '2024-05-01', total_quantity: 140 },
    ];
    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData);

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
    expect(utils.linearRegression).toHaveBeenCalled();
    expect(result.confidence).toBe('High');
    expect(result.analysis).toBe('Mock demand forecast insights');
  });

  it('should return a low confidence forecast for insufficient data', async () => {
    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue([]);

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(result.confidence).toBe('Low');
    expect(result.analysis).toContain('not enough historical sales data');
    expect(utils.linearRegression).not.toHaveBeenCalled();
  });
});