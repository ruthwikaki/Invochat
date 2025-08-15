
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Message } from '@/types';
import type { Mock } from 'vitest';

// Mock dependencies
vi.mock('@/lib/error-handler');
vi.mock('@/services/database');
vi.mock('@/config/app-config', () => ({
  config: {
    ai: { model: 'mock-model', maxOutputTokens: 1024 },
  }
}));
vi.mock('crypto', () => ({
  default: {
    createHash: vi.fn().mockReturnValue({
      update: vi.fn().mockReturnThis(),
      digest: vi.fn().mockReturnValue('mocked-hash'),
    }),
  }
}));
vi.mock('@/lib/redis', () => ({
  isRedisEnabled: false,
  redisClient: {
    get: vi.fn().mockResolvedValue(null),
    set: vi.fn().mockResolvedValue('OK'),
  }
}));

// Mock all tool imports from the universal chat flow
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
    getDemandForecast: vi.fn(), getAbcAnalysis: vi.fn(), getGrossMarginAnalysis: vi.fn(),
    getNetMarginByChannel: vi.fn(), getMarginTrends: vi.fn(), getSalesVelocity: vi.fn(),
    getPromotionalImpactAnalysis: vi.fn()
}));

vi.mock('@/ai/genkit', () => ({
    ai: {
        defineFlow: vi.fn((_, impl) => impl),
        definePrompt: vi.fn(() => vi.fn()),
        generate: vi.fn(),
    },
}));


import { universalChatFlow } from '@/ai/flows/universal-chat';
import * as redis from '@/lib/redis';
import { ai } from '@/ai/genkit';

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory: Partial<Message>[] = [
    { role: 'user', content: [{ text: mockUserQuery }] as any }
];

const mockFinalResponse = {
    response: "You should reorder these items.",
    data: [{ sku: 'SKU001', quantity: 50 }],
    visualization: { type: 'table', title: 'Reorder Suggestions', data: [] as any[] },
    confidence: 0.9,
    assumptions: [],
    toolName: 'getReorderSuggestions'
};

describe('Universal Chat Flow', () => {
    let mockPromptFn: Mock;

    beforeEach(() => {
        vi.clearAllMocks();
        mockPromptFn = (ai.definePrompt as Mock).mock.results[0].value;
    });

    it('should call a tool and format the final response', async () => {
        (redis.isRedisEnabled as any) = false;
        (ai.generate as Mock).mockResolvedValue({
            toolRequests: [{ name: 'getReorderSuggestions', input: { companyId: mockCompanyId } }],
            text: ''
        });
        
        mockPromptFn.mockResolvedValue({ output: mockFinalResponse });

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(ai.generate).toHaveBeenCalledWith(expect.anything());
        expect(mockPromptFn).toHaveBeenCalled();
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        (redis.isRedisEnabled as any) = false;
        (ai.generate as Mock).mockResolvedValue({
            text: 'I cannot help with that.',
            toolRequests: [],
        });
        
        mockPromptFn.mockResolvedValue({ output: { response: "I cannot help with that." } });

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        await universalChatFlow(input);
        
        expect(mockPromptFn).toHaveBeenCalledWith(
            expect.objectContaining({ userQuery: mockUserQuery, toolResult: 'I cannot help with that.' }),
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        (redis.isRedisEnabled as any) = true;
        const redisGetMock = (redis.redisClient.get as Mock).mockResolvedValue(JSON.stringify(mockFinalResponse));

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalledWith('aichat:test-company-id:mocked-hash');
        expect(ai.generate).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
    
    it('should handle errors gracefully', async () => {
       (redis.isRedisEnabled as any) = false;
       (ai.generate as Mock).mockRejectedValue(new Error('Service unavailable'));

       const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
       const result = await universalChatFlow(input);

        expect(result.response).toContain('AI service is currently unavailable');
        expect(result.confidence).toBe(0.0);
        expect(result.is_error).toBe(true);
    });
});
