
import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/lib/redis');
vi.mock('@/lib/error-handler', () => ({
  logError: vi.fn(),
  getErrorMessage: vi.fn(e => (e as Error)?.message || String(e) || ''),
}));
vi.mock('@/services/database');
vi.mock('@/config/app-config', () => ({
  config: { 
      ai: { model: 'mock-model', maxOutputTokens: 1024 },
    }
}));

// Mock all the tools that are imported by universal-chat
vi.mock('@/ai/flows/economic-tool', () => ({ getEconomicIndicators: vi.fn() }));
vi.mock('@/ai/flows/dead-stock-tool', () => ({ getDeadStockReport: vi.fn() }));
vi.mock('@/ai/flows/inventory-turnover-tool', () => ({ getInventoryTurnoverReport: vi.fn() }));
vi.mock('@/ai/flows/reorder-tool', () => ({ getReorderSuggestions: vi.fn() }));
vi.mock('@/ai/flows/analyze-supplier-flow', () => ({ getSupplierAnalysisTool: vi.fn() }));
vi.mock('@/ai/flows/markdown-optimizer-flow', () => ({ getMarkdownSuggestions: vi.fn() }));
vi.mock('@/ai/flows/price-optimization-flow', () => ({ getPriceOptimizationSuggestions: vi.fn() }));
vi.mock('@/ai/flows/suggest-bundles-flow', () => ({ getBundleSuggestions: vi.fn() }));
vi.mock('@/ai/flows/hidden-money-finder-flow', () => ({ findHiddenMoney: vi.fn() }));
vi.mock('@/ai/flows/product-demand-forecast-flow', () => ({ getProductDemandForecast: vi.fn() }));
vi.mock('@/ai/flows/analytics-tools', () => ({
    getDemandForecast: vi.fn(),
    getAbcAnalysis: vi.fn(),
    getGrossMarginAnalysis: vi.fn(),
    getNetMarginByChannel: vi.fn(),
    getMarginTrends: vi.fn(),
    getSalesVelocity: vi.fn(),
    getPromotionalImpactAnalysis: vi.fn()
}));

// Fix: Create mock functions INSIDE the factory
vi.mock('@/ai/genkit', () => {
  return {
    ai: {
      defineFlow: vi.fn((_, impl) => impl),
      definePrompt: vi.fn(),
      generate: vi.fn(),
    },
  };
});

import { universalChatFlow } from '@/ai/flows/universal-chat';
import * as redis from '@/lib/redis';
import { ai } from '@/ai/genkit';
import { getErrorMessage } from '@/lib/error-handler';

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory = [
    { role: 'user', content: [{ text: mockUserQuery }] }
];

const mockFinalResponse = {
    response: "You should reorder these items.",
    data: [{ sku: 'SKU001', quantity: 50 }],
    visualization: { type: 'table', title: 'Reorder Suggestions', data: [] },
    confidence: 0.9,
    assumptions: [],
    toolName: 'getReorderSuggestions'
};

describe('Universal Chat Flow', () => {
    let mockPromptFn: any;

    beforeEach(() => {
        vi.clearAllMocks();
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(false);
        mockPromptFn = vi.fn();
        (ai.definePrompt as any).mockReturnValue(mockPromptFn);
    });

    it('should call a tool and format the final response', async () => {
        (ai.generate as vi.Mock).mockResolvedValue({
            toolRequests: [{ name: 'getReorderSuggestions', input: { companyId: mockCompanyId } }],
            text: ''
        });
        
        mockPromptFn.mockResolvedValue({ output: mockFinalResponse });

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(ai.generate).toHaveBeenCalledWith(expect.anything());
        expect(mockPromptFn).toHaveBeenCalled();
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        (ai.generate as vi.Mock).mockResolvedValue({
            text: 'I cannot help with that.',
            toolRequests: [],
        });
        
        mockPromptFn.mockResolvedValue({ output: { response: "I cannot help with that." } });

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        await universalChatFlow(input);
        
        expect(mockPromptFn).toHaveBeenCalledWith(
            expect.objectContaining({ userQuery: mockUserQuery, toolResult: 'I cannot help with that.' }),
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(true);
        const redisGetMock = vi.spyOn(redis.redisClient, 'get').mockResolvedValue(JSON.stringify(mockFinalResponse));

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalled();
        expect(ai.generate).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
});
