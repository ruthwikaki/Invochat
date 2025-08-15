import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupplierPerformanceReport } from '@/types';

// 🚨 CRITICAL: Mock dependencies BEFORE importing the flow
vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

// Create a mock prompt that we can control in tests
const mockPromptFunction = vi.fn();

vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: vi.fn(() => mockPromptFunction),
    defineFlow: vi.fn((config, implementation) => implementation),
    defineTool: vi.fn((config, implementation) => implementation),
  },
}));

// NOW we can safely import the flows
import { analyzeSuppliersFlow, getSupplierAnalysisTool } from '@/ai/flows/analyze-supplier-flow';
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
    vi.clearAllMocks();
    
    // Set up the default mock prompt response
    mockPromptFunction.mockResolvedValue({
      output: {
        analysis: "Mock supplier analysis",
        bestSupplier: "Best Mock Supplier"
      }
    });
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(mockPromptFunction).toHaveBeenCalled();
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
  });

  it('should throw an error if the AI analysis fails', async () => {
    (database.getSupplierPerformanceFromDB as vi.Mock).mockResolvedValue(mockPerformanceData);
    
    // Override the mock for this specific test
    mockPromptFunction.mockResolvedValueOnce({ output: null });

    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });

  it('should be exposed as a Genkit tool', () => {
    expect(getSupplierAnalysisTool).toBeDefined();
  });
});
