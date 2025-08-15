import { describe, it, expect, vi, beforeEach } from 'vitest';
import { analyzeSuppliersFlow, getSupplierAnalysisTool } from '@/ai/flows/analyze-supplier-flow';
import * as database from '@/services/database';
import { ai } from '@/ai/genkit';
import type { SupplierPerformanceReport } from '@/types';

// Mock dependencies
vi.mock('@/services/database');
vi.mock('@/ai/genkit', async () => {
  const { defineTool, defineFlow, definePrompt } = await vi.importActual('genkit');
  return {
    ai: {
      defineTool: vi.fn((...args) => defineTool(...args)),
      defineFlow: vi.fn((...args) => defineFlow(...args)),
      definePrompt: vi.fn((...args) => definePrompt(...args)),
      generate: vi.fn(),
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
    // This setup correctly mocks the result of the prompt call
    (ai.generate as vi.Mock).mockResolvedValue({
      output: () => mockAiResponse
    });
    vi.mocked(ai.definePrompt).mockReturnValue(vi.fn().mockResolvedValue({ output: mockAiResponse }));
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(ai.definePrompt).toHaveBeenCalled();
    expect(result.bestSupplier).toBe('Supplier A');
    expect(result.analysis).toContain('higher average profit margin');
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
    vi.mocked(ai.definePrompt).mockReturnValue(vi.fn().mockResolvedValue({ output: null }));

    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });
});
