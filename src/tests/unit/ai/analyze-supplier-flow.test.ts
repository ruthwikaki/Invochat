import { describe, it, expect, vi, beforeEach } from 'vitest';
import { analyzeSuppliersFlow, getSupplierAnalysisTool } from '@/ai/flows/analyze-supplier-flow';
import * as database from '@/services/database';
import { ai } from '@/ai/genkit';
import type { SupplierPerformanceReport } from '@/types';

// Mock dependencies
vi.mock('@/services/database');

const defineToolMock = vi.fn((config, func) => func);
const definePromptMock = vi.fn();
const defineFlowMock = vi.fn((_config, func) => func);

vi.mock('@/ai/genkit', () => ({
  ai: {
    defineTool: defineToolMock,
    definePrompt: definePromptMock,
    defineFlow: defineFlowMock,
  },
}));


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
  let supplierAnalysisPrompt: any;

  beforeEach(() => {
    vi.resetAllMocks();
    supplierAnalysisPrompt = vi.fn().mockResolvedValue({ output: mockAiResponse });
    definePromptMock.mockReturnValue(supplierAnalysisPrompt);
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(supplierAnalysisPrompt).toHaveBeenCalledWith({ performanceData: mockPerformanceData }, expect.anything());
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
    expect(supplierAnalysisPrompt).not.toHaveBeenCalled();
  });

  it('should throw an error if the AI analysis fails', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);
    supplierAnalysisPrompt.mockResolvedValue({ output: null });

    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });

  it('should be exposed as a Genkit tool', () => {
    expect(getSupplierAnalysisTool).toBeDefined();
    expect(defineToolMock).toHaveBeenCalledWith(expect.objectContaining({ name: 'getSupplierPerformanceAnalysis' }), expect.any(Function));
  });
});
