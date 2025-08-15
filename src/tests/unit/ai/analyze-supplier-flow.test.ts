import { describe, it, expect, vi, beforeEach } from 'vitest';
import { analyzeSuppliersFlow, getSupplierAnalysisTool } from '@/ai/flows/analyze-supplier-flow';
import * as database from '@/services/database';
import { ai } from '@/ai/genkit';
import type { SupplierPerformanceReport } from '@/types';

// Mock dependencies
vi.mock('@/services/database');
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
            analysis: "Mock supplier analysis",
            bestSupplier: "Best Mock Supplier"
          }
        }));
        mockPrompt.config = config;
        return mockPrompt;
      }),
    },
  };
});

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

const mockAiResponse = {
  analysis: "Supplier A is recommended due to their significantly higher average profit margin (50%) and excellent sell-through rate.",
  bestSupplier: "Supplier A",
};

describe('Analyze Supplier Flow', () => {

  beforeEach(() => {
    vi.clearAllMocks();
    (ai.definePrompt as any).mockImplementation((config: any) => {
        const mockPrompt = vi.fn(async () => ({ 
          output: mockAiResponse
        }));
        mockPrompt.config = config;
        return mockPrompt;
    });
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(ai.definePrompt).toHaveBeenCalled();
    expect(result.bestSupplier).toBe('Best Mock Supplier');
    expect(result.analysis).toBe('Mock supplier analysis');
    expect(result.performanceData).toEqual(mockPerformanceData);
  });

  it('should handle cases where there is no performance data', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue([]);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(result.analysis).toContain('not enough data');
    expect(result.bestSupplier).toBe('N/A');
    expect(result.performanceData).toEqual([]);
    expect(ai.definePrompt).not.toHaveBeenCalled();
  });

  it('should throw an error if the AI analysis fails', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);
    // Mock the prompt to return a null output
    (ai.definePrompt as any).mockImplementation((config: any) => {
        const mockPrompt = vi.fn(async () => ({ output: null }));
        mockPrompt.config = config;
        return mockPrompt;
    });

    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });

  it('should be exposed as a Genkit tool', () => {
    expect(getSupplierAnalysisTool).toBeDefined();
  });
});
