
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupplierPerformanceReport } from '@/types';

// 🚨 CRITICAL: Mock dependencies BEFORE importing the flow
vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

// Import mocked modules
import * as database from '@/services/database';

const mockPerformanceData: SupplierPerformanceReport[] = [
  {
    supplier_name: 'Supplier A',
    total_profit: 200000,
    average_margin: 50.0,
    sell_through_rate: 0.9,
    total_sales_count: 100,
    distinct_products_sold: 5,
    on_time_delivery_rate: 95,
    average_lead_time_days: 10,
    total_completed_orders: 20,
  },
  {
    supplier_name: 'Supplier B',
    total_profit: 150000,
    average_margin: 40.0,
    sell_through_rate: 0.8,
    total_sales_count: 120,
    distinct_products_sold: 10,
    on_time_delivery_rate: 90,
    average_lead_time_days: 15,
    total_completed_orders: 25,
  },
];

describe('Analyze Supplier Flow', () => {

  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    // Mock ai module for this specific test
    vi.doMock('@/ai/genkit', () => ({
      ai: {
        definePrompt: vi.fn().mockReturnValue(
          vi.fn().mockResolvedValue({
            output: {
              analysis: "Mock supplier analysis",
              bestSupplier: "Best Mock Supplier"
            }
          })
        ),
        defineFlow: vi.fn((_, impl) => impl),
        defineTool: vi.fn((_, impl) => impl),
      },
    }));

    (database.getSupplierPerformanceFromDB as any).mockResolvedValue(mockPerformanceData);

    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    const { ai } = await import('@/ai/genkit');
    
    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(ai.definePrompt().mock.results[0].value).toHaveBeenCalled();
    expect(result.bestSupplier).toBe('Best Mock Supplier');
    expect(result.analysis).toBe('Mock supplier analysis');
    expect(result.performanceData).toEqual(mockPerformanceData);
  });

  it('should handle cases where there is no performance data', async () => {
    vi.doMock('@/ai/genkit', () => ({
      ai: {
        defineFlow: vi.fn((_, impl) => impl),
        defineTool: vi.fn(), // Must mock defineTool even if not used directly
      },
    }));

    (database.getSupplierPerformanceFromDB as any).mockResolvedValue([]);
    
    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    
    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(result.analysis).toContain('not enough data');
    expect(result.bestSupplier).toBe('N/A');
    expect(result.performanceData).toEqual([]);
  });

  it('should throw an error if the AI analysis fails', async () => {
    vi.doMock('@/ai/genkit', () => ({
      ai: {
        definePrompt: vi.fn().mockReturnValue(
          vi.fn().mockResolvedValue({ output: null }) // Simulate AI returning null
        ),
        defineFlow: vi.fn((_, impl) => impl),
        defineTool: vi.fn(),
      },
    }));
    
    (database.getSupplierPerformanceFromDB as any).mockResolvedValue(mockPerformanceData);
    
    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    
    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });

  it('should be exposed as a Genkit tool', async () => {
     vi.doMock('@/ai/genkit', () => ({
      ai: {
        defineTool: vi.fn(),
        defineFlow: vi.fn((_, impl) => impl),
      },
    }));
    
    const { getSupplierAnalysisTool } = await import('@/ai/flows/analyze-supplier-flow');
    const { ai } = await import('@/ai/genkit');
    
    expect(ai.defineTool).toHaveBeenCalled();
    expect(getSupplierAnalysisTool).toBeDefined();
  });
});
