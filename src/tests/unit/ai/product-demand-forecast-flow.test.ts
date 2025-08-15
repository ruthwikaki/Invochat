import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/lib/utils', () => ({
  linearRegression: vi.fn(() => ({ slope: 5, intercept: 100 })),
  differenceInDays: vi.fn((a,b) => (new Date(a).getTime() - new Date(b).getTime()) / (1000 * 3600 * 24)),
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

const mockSalesData = [
    { sale_date: '2024-01-01T00:00:00Z', total_quantity: 10 },
    { sale_date: '2024-01-02T00:00:00Z', total_quantity: 12 },
    { sale_date: '2024-01-03T00:00:00Z', total_quantity: 11 },
    { sale_date: '2024-01-04T00:00:00Z', total_quantity: 13 },
    { sale_date: '2024-01-05T00:00:00Z', total_quantity: 15 },
];


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
    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData);

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
    expect(utils.linearRegression).toHaveBeenCalled();
    expect(result.confidence).toBe('High');
    expect(result.analysis).toBe('Mock demand forecast insights');
  });

  it('should return a low confidence forecast for insufficient data', async () => {
    (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData.slice(0,3));

    const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
    const result = await productDemandForecastFlow(input);

    expect(result.confidence).toBe('Low');
    expect(result.analysis).toContain('not enough historical sales data');
    expect(utils.linearRegression).not.toHaveBeenCalled();
  });
});
