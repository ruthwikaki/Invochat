
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { analyzeSuppliersFlow } from '@/ai/flows/analyze-supplier-flow';
import * as database from '@/services/database';
import * as genkit from '@/ai/genkit';
import type { SupplierPerformanceReport } from '@/types';

// Mock dependencies
vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: vi.fn(() => vi.fn()),
    defineFlow: vi.fn((_config, func) => func), // Immediately return the flow function
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
    // Mock the prompt function that the flow will call
    supplierAnalysisPrompt = vi.fn().mockResolvedValue({ output: mockAiResponse });
    vi.spyOn(genkit.ai, 'definePrompt').mockReturnValue(supplierAnalysisPrompt);
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    // Verify that the database was called correctly
    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);

    // Verify that the AI prompt was called with the correct data
    expect(supplierAnalysisPrompt).toHaveBeenCalledWith({ performanceData: mockPerformanceData }, expect.anything());

    // Verify that the final output combines data from the DB and the AI
    expect(result.bestSupplier).toBe('Supplier A');
    expect(result.analysis).toContain('higher average profit margin');
    expect(result.performanceData).toEqual(mockPerformanceData);
  });

  it('should handle cases where there is no performance data', async () => {
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockResolvedValue([]);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(result.analysis).toContain('not enough data');
    expect(result.bestSupplier).toBe('N/A');
    expect(result.performanceData).toEqual([]);
    // Ensure the AI prompt is not called if there's no data
    expect(supplierAnalysisPrompt).not.toHaveBeenCalled();
  });

  it('should throw an error if the AI analysis fails', async () => {
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockResolvedValue(mockPerformanceData);
    // Mock the AI prompt to return no output
    supplierAnalysisPrompt.mockResolvedValue({ output: null });

    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('An error occurred while analyzing supplier performance.');
  });
});

