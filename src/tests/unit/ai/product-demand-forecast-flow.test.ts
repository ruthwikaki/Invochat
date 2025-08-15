import { describe, it, expect, vi, beforeEach } from 'vitest';
import { productDemandForecastFlow } from '@/ai/flows/product-demand-forecast-flow';
import * as database from '@/services/database';
import * as utils from '@/lib/utils';
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
            confidence: 'Medium',
            analysis: "Sales for this product show a clear upward trend. Based on this, I predict you will sell approximately 450 units in the next 30 days.",
            trend: 'Upward',
          }
        }));
        mockPrompt.config = config;
        return mockPrompt;
      }),
    },
  };
});
vi.mock('@/services/database');
vi.mock('@/lib/utils');


const mockSalesData = [
    { sale_date: '2024-01-01T00:00:00Z', total_quantity: 10 },
    { sale_date: '2024-01-02T00:00:00Z', total_quantity: 12 },
    { sale_date: '2024-01-03T00:00:00Z', total_quantity: 11 },
    { sale_date: '2024-01-04T00:00:00Z', total_quantity: 13 },
    { sale_date: '2024-01-05T00:00:00Z', total_quantity: 15 },
];

describe('Product Demand Forecast Flow', () => {

    beforeEach(() => {
        vi.resetAllMocks();
        (utils.linearRegression as vi.Mock).mockReturnValue({ slope: 1, intercept: 10 });
    });

    it('should forecast demand for a product with sufficient sales data', async () => {
        (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData);

        const input = { companyId: 'test-company-id', sku: 'SKU001', daysToForecast: 30 };
        const result = await productDemandForecastFlow(input);

        expect(database.getHistoricalSalesForSingleSkuFromDB).toHaveBeenCalledWith(input.companyId, input.sku);
        expect(utils.linearRegression).toHaveBeenCalled();
        expect(ai.definePrompt).toHaveBeenCalled();
        expect(result.forecastedDemand).toBeGreaterThan(0);
        expect(result.trend).toBe('Upward');
        expect(result.analysis).toContain('upward trend');
    });

    it('should return a low confidence forecast for insufficient data', async () => {
        (database.getHistoricalSalesForSingleSkuFromDB as vi.Mock).mockResolvedValue(mockSalesData.slice(0, 3));
        const input = { companyId: 'test-company-id', sku: 'SKU002', daysToForecast: 30 };
        const result = await productDemandForecastFlow(input);

        expect(result.confidence).toBe('Low');
        expect(result.analysis).toContain('not enough historical sales data');
        expect(utils.linearRegression).not.toHaveBeenCalled();
    });
});
