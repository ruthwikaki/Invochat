
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupplierPerformanceReport } from '@/types';

// 🚨 CRITICAL: Mock dependencies BEFORE importing the flow
vi.mock('@/services/database');
vi.mock('@/lib/error-handler');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model' } }
}));

// Mock AI module at the top level
const mockPromptFunction = vi.fn();
const mockDefinePrompt = vi.fn().mockReturnValue(mockPromptFunction);
const mockDefineFlow = vi.fn((_, impl) => impl);
const mockDefineTool = vi.fn().mockReturnValue('mock-tool');

vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: mockDefinePrompt,
    defineFlow: mockDefineFlow,
    defineTool: mockDefineTool,
  },
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
    // Only clear the database mock and prompt function mock
    (database.getSupplierPerformanceFromDB as any).mockClear?.();
    mockPromptFunction.mockClear();
  });

  it('should fetch supplier performance data and generate an analysis', async () => {
    // Set up specific mock behavior for this test
    mockPromptFunction.mockResolvedValue({
      output: {
        analysis: "Mock supplier analysis",
        bestSupplier: "Best Mock Supplier"
      }
    });

    (database.getSupplierPerformanceFromDB as any).mockResolvedValue(mockPerformanceData);

    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    
    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(mockDefinePrompt).toHaveBeenCalled();
    expect(mockPromptFunction).toHaveBeenCalledWith(
      { performanceData: mockPerformanceData },
      { model: 'mock-model' }
    );
    expect(result.bestSupplier).toBe('Best Mock Supplier');
    expect(result.analysis).toBe('Mock supplier analysis');
    expect(result.performanceData).toEqual(mockPerformanceData);
  });

  it('should handle cases where there is no performance data', async () => {
    (database.getSupplierPerformanceFromDB as any).mockResolvedValue([]);
    
    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    
    const input = { companyId: 'test-company-id' };
    const result = await analyzeSuppliersFlow(input);

    expect(result.analysis).toContain('not enough data');
    expect(result.bestSupplier).toBe('N/A');
    expect(result.performanceData).toEqual([]);
  });

  it('should throw an error if the AI analysis fails', async () => {
    // Set up mock to return null output
    mockPromptFunction.mockResolvedValue({ output: null });
    
    (database.getSupplierPerformanceFromDB as any).mockResolvedValue(mockPerformanceData);
    
    const { analyzeSuppliersFlow } = await import('@/ai/flows/analyze-supplier-flow');
    
    const input = { companyId: 'test-company-id' };

    await expect(analyzeSuppliersFlow(input)).rejects.toThrow('AI analysis of supplier performance failed to return an output.');
  });

  it('should be exposed as a Genkit tool', async () => {
    // Import the module and verify the tool export exists
    const { getSupplierAnalysisTool } = await import('@/ai/flows/analyze-supplier-flow');
    
    // Verify the tool exists and is the mocked return value
    expect(getSupplierAnalysisTool).toBe('mock-tool');
  });
});
