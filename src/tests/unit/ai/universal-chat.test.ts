
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import * as genkit from '@/ai/genkit';
import * as redis from '@/lib/redis';
import type { MessageData, GenerateResponse, ToolRequestPart } from 'genkit';

vi.mock('@/ai/genkit', () => ({
  ai: {
    defineFlow: vi.fn(),
    definePrompt: vi.fn(),
    generate: vi.fn(),
  },
}));

vi.mock('@/lib/redis');

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory: MessageData[] = [
    { role: 'user', content: [{ text: mockUserQuery }] }
];

const mockToolRequestPart: ToolRequestPart = {
    toolRequest: {
        name: 'getReorderSuggestions',
        input: { companyId: mockCompanyId }
    }
};

const mockToolResponse: GenerateResponse = {
    candidates: [{
        index: 0,
        finishReason: 'toolUse',
        message: {
            role: 'model',
            content: [mockToolRequestPart]
        }
    }],
    usage: {},
    custom: {},
    request: { messages: [], tools: [] },
    toolRequests: [mockToolRequestPart.toolRequest],
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
    let finalResponsePromptMock: vi.Mock;

    beforeEach(() => {
        vi.resetAllMocks();
        finalResponsePromptMock = vi.fn().mockResolvedValue({ output: mockFinalResponse });

        // Correctly mock defineFlow to return the actual function
        (genkit.ai.defineFlow as vi.Mock).mockImplementation((_config, func) => func);
        (genkit.ai.definePrompt as vi.Mock).mockReturnValue(finalResponsePromptMock);
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(false);
    });

    it('should call a tool and format the final response', async () => {
        (genkit.ai.generate as vi.Mock).mockResolvedValue(mockToolResponse);

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(genkit.ai.generate).toHaveBeenCalledWith(expect.objectContaining({
            tools: expect.any(Array),
        }));
        expect(finalResponsePromptMock).toHaveBeenCalledWith(
            { userQuery: mockUserQuery, toolResult: { name: 'getReorderSuggestions', input: { companyId: 'test-company-id' } } },
            expect.anything()
        );
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        (genkit.ai.generate as vi.Mock).mockResolvedValue(mockTextResponse);

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        await universalChatFlow(input);
        
        expect(finalResponsePromptMock).toHaveBeenCalledWith(
            { userQuery: mockUserQuery, toolResult: 'I cannot help with that.' },
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(true);
        const redisGetMock = vi.spyOn(redis.redisClient, 'get').mockResolvedValue(JSON.stringify(mockFinalResponse));

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalled();
        expect(genkit.ai.generate).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
});
