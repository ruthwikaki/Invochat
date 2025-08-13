
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getReorderSuggestions } from '@/ai/flows/reorder-tool';
import * as database from '@/services/database';
import * as genkit from '@/ai/genkit';
import type { ReorderSuggestion } from '@/types';
import type { ReorderSuggestion as ReorderSuggestionFromDb } from '@/schemas/reorder';

// Mock database and AI calls
vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    definePrompt: vi.fn(() => vi.fn()),
    defineTool: vi.fn((config, func) => ({ ...config, func })),
  },
}));

const mockBaseSuggestions: ReorderSuggestionFromDb[] = [
  {
    variant_id: 'v1',
    product_id: 'p1',
    sku: 'SKU001',
    product_name: 'Test Product 1',
    supplier_name: 'Test Supplier',
    supplier_id: 's1',
    current_quantity: 5,
    suggested_reorder_quantity: 50,
    unit_cost: 1000,
    base_quantity: 50,
    adjustment_reason: null,
    seasonality_factor: null,
    confidence: null,
  },
];

const mockAiRefinedSuggestions: ReorderSuggestion[] = [
  {
    ...mockBaseSuggestions[0],
    suggested_reorder_quantity: 65, // AI adjusted
    adjustment_reason: 'Increased for expected seasonal demand.',
    seasonality_factor: 1.3,
    confidence: 0.85,
  },
];

describe('Reorder Tool', () => {
  let reorderRefinementPrompt: any;

  beforeEach(() => {
    vi.resetAllMocks();
    // Mock the prompt function that the tool will call
    reorderRefinementPrompt = vi.fn().mockResolvedValue({ output: mockAiRefinedSuggestions });
    vi.spyOn(genkit.ai, 'definePrompt').mockReturnValue(reorderRefinementPrompt);
  });

  it('should return AI-refined reorder suggestions', async () => {
    // Setup mocks for database functions
    vi.spyOn(database, 'getReorderSuggestionsFromDB').mockResolvedValue(mockBaseSuggestions as any);
    vi.spyOn(database, 'getHistoricalSalesForSkus').mockResolvedValue([]);
    vi.spyOn(database, 'getSettings').mockResolvedValue({ timezone: 'UTC' } as any);

    const input = { companyId: 'test-company-id' };
    const result = await (getReorderSuggestions as any).run(input);

    // Verify results
    expect(result).toHaveLength(1);
    expect(result[0].sku).toBe('SKU001');
    expect(result[0].suggested_reorder_quantity).toBe(65);
    expect(result[0].adjustment_reason).toContain('seasonal demand');
    expect(database.getReorderSuggestionsFromDB).toHaveBeenCalledWith(input.companyId);
    expect(reorderRefinementPrompt).toHaveBeenCalled();
  });

  it('should return base suggestions if AI refinement fails', async () => {
    // Mock AI to fail
    reorderRefinementPrompt.mockResolvedValue({ output: null });
    vi.spyOn(database, 'getReorderSuggestionsFromDB').mockResolvedValue(mockBaseSuggestions as any);
    vi.spyOn(database, 'getHistoricalSalesForSkus').mockResolvedValue([]);
    vi.spyOn(database, 'getSettings').mockResolvedValue({ timezone: 'UTC' } as any);

    const input = { companyId: 'test-company-id' };
    const result = await (getReorderSuggestions as any).run(input);

    expect(result).toHaveLength(1);
    expect(result[0].suggested_reorder_quantity).toBe(50); // Fallback to base
    expect(result[0].adjustment_reason).toContain('Using baseline heuristic.');
  });

  it('should handle cases with no initial suggestions', async () => {
    vi.spyOn(database, 'getReorderSuggestionsFromDB').mockResolvedValue([]);
    const input = { companyId: 'test-company-id' };
    const result = await (getReorderSuggestions as any).run(input);

    expect(result).toHaveLength(0);
    expect(reorderRefinementPrompt).not.toHaveBeenCalled();
  });
});

