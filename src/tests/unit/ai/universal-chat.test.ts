import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Message } from '@/types';

// Mock dependencies at the top level
vi.mock('@/lib/error-handler');
vi.mock('@/services/database');
vi.mock('@/config/app-config', () => ({
  config: { 
    ai: { model: 'mock-model', maxOutputTokens: 1024 },
  }
}));

// Mock all tool imports
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
vi.mock('crypto', () => ({
  default: {
    createHash: vi.fn().mockReturnValue({
      update: vi.fn().mockReturnThis(),
      digest: vi.fn().mockReturnValue('mocked-hash'),
    }),
  }
}));


const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory = [
    { role: 'user', content: [{ text: mockUserQuery }] }
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

    beforeEach(() => {
        vi.resetModules();
    });

    it('should call a tool and format the final response', async () => {
        vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: false,
          redisClient: {},
        }));

        vi.doMock('@/ai/genkit', () => ({
            ai: {
                defineFlow: vi.fn((_, impl) => impl),
                definePrompt: vi.fn().mockReturnValue(vi.fn().mockResolvedValue({ output: mockFinalResponse })),
                generate: vi.fn().mockResolvedValue({
                    toolRequests: [{ name: 'getReorderSuggestions', input: { companyId: mockCompanyId } }],
                    text: ''
                }),
            },
        }));

        const { universalChatFlow } = await import('@/ai/flows/universal-chat');
        const { ai } = await import('@/ai/genkit');
        
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(ai.generate).toHaveBeenCalledWith(expect.anything());
        expect(ai.definePrompt).toHaveBeenCalled();
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
         vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: false,
          redisClient: {},
        }));
        
        const mockPromptFn = vi.fn().mockResolvedValue({ output: { response: "I cannot help with that." } });
        vi.doMock('@/ai/genkit', () => ({
             ai: {
                defineFlow: vi.fn((_, impl) => impl),
                definePrompt: vi.fn(() => mockPromptFn),
                generate: vi.fn().mockResolvedValue({
                    text: 'I cannot help with that.',
                    toolRequests: [],
                }),
            },
        }));
        
        const { universalChatFlow } = await import('@/ai/flows/universal-chat');

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        await universalChatFlow(input);
        
        expect(mockPromptFn).toHaveBeenCalledWith(
            expect.objectContaining({ userQuery: mockUserQuery, toolResult: 'I cannot help with that.' }),
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        vi.doMock('@/lib/redis', () => ({
            isRedisEnabled: true,
            redisClient: {
                get: vi.fn().mockResolvedValue(JSON.stringify(mockFinalResponse)),
                set: vi.fn()
            }
        }));
        vi.doMock('@/ai/genkit', () => ({
            ai: {
                defineFlow: vi.fn((_, impl) => impl),
            },
        }));
        
        const { universalChatFlow } = await import('@/ai/flows/universal-chat');
        const { redisClient } = await import('@/lib/redis');

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(redisClient.get).toHaveBeenCalledWith('aichat:test-company-id:mocked-hash');
        expect(result.response).toBe(mockFinalResponse.response);
    });
    
    it('should handle errors gracefully', async () => {
       vi.doMock('@/lib/redis', () => ({ isRedisEnabled: false }));
       vi.doMock('@/ai/genkit', () => ({
            ai: {
                defineFlow: vi.fn((_, impl) => impl),
                generate: vi.fn().mockRejectedValue(new Error('Service unavailable')),
            },
       }));

       const { universalChatFlow } = await import('@/ai/flows/universal-chat');
       
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(result.response).toContain('AI service is currently unavailable');
        expect(result.confidence).toBe(0.0);
        expect(result.is_error).toBe(true);
    });

});
