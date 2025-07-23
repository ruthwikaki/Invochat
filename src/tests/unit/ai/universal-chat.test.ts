
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { universalChatFlow } from '@/ai/flows/universal-chat';
import * as genkit from '@/ai/genkit';
import * as redis from '@/lib/redis';
import type { MessageData, GenerateResponse } from 'genkit';

vi.mock('@/ai/genkit');
vi.mock('@/lib/redis');

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory: MessageData[] = [
    { role: 'user', content: [{ text: mockUserQuery }] }
];

const mockToolResponse: GenerateResponse = {
    candidates: [{
        index: 0,
        finishReason: 'toolUse',
        message: {
            role: 'model',
            content: [],
            toolRequests: [{
                name: 'getReorderSuggestions',
                input: { companyId: mockCompanyId }
            }]
        }
    }],
    usage: {},
    custom: {},
    request: { messages: [], tools: [], model: 'googleai/gemini-1.5-pro' }
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
    request: { messages: [], tools: [], model: 'googleai/gemini-1.5-pro' }
};

const mockFinalResponse = {
    response: "You should reorder these items.",
    data: [{ sku: 'SKU001', quantity: 50 }],
    visualization: { type: 'table', title: 'Reorder Suggestions' },
    confidence: 0.9,
    assumptions: [],
    toolName: 'getReorderSuggestions'
};

describe('Universal Chat Flow', () => {
    let generateMock: vi.Mock;
    let finalResponsePromptMock: vi.Mock;

    beforeEach(() => {
        vi.resetAllMocks();
        generateMock = vi.fn();
        finalResponsePromptMock = vi.fn().mockResolvedValue({ output: mockFinalResponse });

        vi.spyOn(genkit.ai, 'generate').mockImplementation(generateMock);
        vi.spyOn(genkit.ai, 'defineFlow').mockImplementation((config, func) => func as any);
        vi.spyOn(genkit.ai, 'definePrompt').mockImplementation(() => finalResponsePromptMock);
        vi.spyOn(redis, 'isRedisEnabled', 'get').mockReturnValue(false);
    });

    it('should call a tool and format the final response', async () => {
        generateMock.mockResolvedValue(mockToolResponse);

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as any };
        const result = await universalChatFlow(input);

        expect(generateMock).toHaveBeenCalledWith(expect.objectContaining({
            toolChoice: 'auto',
        }));
        expect(finalResponsePromptMock).toHaveBeenCalledWith(
            { userQuery: mockUserQuery, toolResult: { companyId: mockCompanyId } },
            expect.anything()
        );
        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        generateMock.mockResolvedValue(mockTextResponse);

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
        expect(generateMock).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
});
