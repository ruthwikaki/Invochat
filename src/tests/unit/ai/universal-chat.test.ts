
import { describe, it, expect, vi, beforeEach } from 'vitest';

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

const mockUserQuery = 'What should I reorder?';
const mockCompanyId = 'test-company-id';

const mockConversationHistory = [
    { role: 'user' as const, content: [{ text: mockUserQuery }] }
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
        vi.clearAllMocks();
    });

    it('should call a tool and format the final response', async () => {
        vi.doMock('@/lib/redis', () => ({ isRedisEnabled: false, redisClient: {} }));

        const finalResponsePromptMock = vi.fn().mockResolvedValue({ output: mockFinalResponse });
        const generateMock = vi.fn().mockResolvedValue({
            toolRequests: [{ toolRequest: { name: 'getReorderSuggestions', input: { companyId: mockCompanyId } } }],
            text: ''
        });
        
        vi.doMock('@/ai/genkit', () => ({
            ai: {
                defineFlow: vi.fn((_, impl) => impl),
                definePrompt: vi.fn().mockReturnValue(finalResponsePromptMock),
                defineTool: vi.fn().mockReturnValue(vi.fn()),
                generate: generateMock,
            },
        }));

        const { universalChatFlow } = await import('@/ai/flows/universal-chat');
        
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory };
        const result = await universalChatFlow(input);

        expect(result.toolName).toBe('getReorderSuggestions');
        expect(result.response).toContain('You should reorder these items.');
    });

    it('should handle a text-only response from the AI', async () => {
        vi.doMock('@/lib/redis', () => ({ isRedisEnabled: false, redisClient: {} }));
        const finalResponsePromptMock = vi.fn().mockResolvedValue({ output: { response: "I cannot help with that." } });
        const generateMock = vi.fn().mockResolvedValue({
            text: 'I cannot help with that.',
            toolRequests: [],
        });
        
        vi.doMock('@/ai/genkit', () => ({
            ai: {
                defineFlow: vi.fn((_, impl) => impl),
                definePrompt: vi.fn().mockReturnValue(finalResponsePromptMock),
                defineTool: vi.fn().mockReturnValue(vi.fn()),
                generate: generateMock,
            },
        }));

        const { universalChatFlow } = await import('@/ai/flows/universal-chat');

        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory };
        await universalChatFlow(input);
        
        expect(finalResponsePromptMock).toHaveBeenCalledWith(
            expect.objectContaining({ userQuery: mockUserQuery, toolResult: 'I cannot help with that.' }),
            expect.anything()
        );
    });

    it('should use the Redis cache when available', async () => {
        const redisGetMock = vi.fn().mockResolvedValue(JSON.stringify(mockFinalResponse));
        vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: true,
          redisClient: { get: redisGetMock },
        }));

        const generateMock = vi.fn();
        vi.doMock('@/ai/genkit', () => ({
          ai: { 
            defineFlow: vi.fn((_, impl) => impl),
            definePrompt: vi.fn(),
            defineTool: vi.fn().mockReturnValue(vi.fn()),
            generate: generateMock 
          }
        }));

        const { universalChatFlow } = await import('@/ai/flows/universal-chat');
        
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalledWith('aichat:test-company-id:mocked-hash');
        expect(generateMock).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
    
    it('should handle errors gracefully', async () => {
       vi.doMock('@/lib/redis', () => ({ isRedisEnabled: false, redisClient: {} }));

       const generateMock = vi.fn().mockRejectedValue(new Error('Service unavailable'));
       vi.doMock('@/ai/genkit', () => ({
          ai: {
            defineFlow: vi.fn((_, impl) => impl),
            definePrompt: vi.fn(),
            defineTool: vi.fn().mockReturnValue(vi.fn()),
            generate: generateMock,
          }
       }));

       const { universalChatFlow } = await import('@/ai/flows/universal-chat');
       
       const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory };
       const result = await universalChatFlow(input);

        expect(result.response).toContain('I encountered an unexpected error');
        expect(result.confidence).toBe(0.0);
        expect(result.is_error).toBe(true);
    });
});
