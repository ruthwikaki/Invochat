import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { MessageData, GenerateResponse, ToolRequest, GenerateOptions } from 'genkit';

vi.mock('@/lib/redis');
vi.mock('@/lib/error-handler');
vi.mock('@/services/database');
vi.mock('@/config/app-config', () => ({
  config: { ai: { model: 'mock-model', maxOutputTokens: 1024 } }
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


const mockFinalResponsePrompt = vi.fn();
const mockGenerate = vi.fn();

vi.mock('@/ai/genkit', () => ({
    ai: {
      defineFlow: vi.fn((config, implementation) => implementation),
      definePrompt: vi.fn(() => mockFinalResponsePrompt),
      generate: mockGenerate,
    },
}));


import { universalChatFlow } from '@/ai/flows/universal-chat';
import * as redis from '@/lib/redis';

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory: MessageData[] = [
    { role: 'user', content: [{ text: mockUserQuery }] }
];

const mockToolRequestPart: ToolRequest = {
    name: 'getReorderSuggestions',
    input: { companyId: mockCompanyId }
};

const mockToolResponse: GenerateResponse = {
    candidates: [{
        index: 0,
        finishReason: 'toolUse',
        message: {
            role: 'model',
            content: [{ toolRequest: mockToolRequestPart }]
        }
    }],
    usage: {},
    custom: {},
    request: { messages: [], tools: [] },
    toolRequests: [mockToolRequestPart],
    text: ''
};

const mockTextResponse: GenerateResponse = {
    candidates: [{
        index: 0,
        finishReason: 'stop',
        message: {
            role: 'model',
            content: [{ text: 'I cannot help with that.' }]
        }
    }],
    usage: {},
    custom: {},
    request: { messages: [], tools: [] },
    toolRequests: [],
    text: 'I cannot help with that.'
};

const mockFinalResponse = {
    response: "You should reorder these items.",
    data: [{ sku: 'SKU001', quantity: 50 }],
    visualization: { type: 'table', title: 'Reorder Suggestions', data: [] },
    confidence: 0.9,
    assumptions: [],
    toolName: 'getReorderSuggestions'
};

describe('Universal Chat Flow', () => {
    beforeEach(() => {
        vi.resetAllMocks();
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(false);
        mockFinalResponsePrompt.mockResolvedValue({ output: mockFinalResponse });
    });

    it('should call a tool and format the final response', async () => {
        mockGenerate.mockResolvedValue(mockToolResponse);

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(mockGenerate).toHaveBeenCalledWith(expect.objectContaining({
            tools: expect.any(Array),
        }));
        expect(mockFinalResponsePrompt).toHaveBeenCalledWith(
            { userQuery: mockUserQuery, toolResult: mockToolRequestPart.input },
            expect.anything()
        );
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        mockGenerate.mockResolvedValue(mockTextResponse);

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        await universalChatFlow(input);
        
        expect(mockFinalResponsePrompt).toHaveBeenCalledWith(
            { userQuery: mockUserQuery, toolResult: mockTextResponse.text },
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(true);
        const redisGetMock = vi.spyOn(redis.redisClient, 'get').mockResolvedValue(JSON.stringify(mockFinalResponse));

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalled();
        expect(mockGenerate).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
});
