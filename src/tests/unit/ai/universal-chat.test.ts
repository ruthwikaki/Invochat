
import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { Message } from '@/types';

// Mock all external dependencies at the top level
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

// Import the mocked redis module to use its mocked functions
import * as redis from '@/lib/redis';

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

    beforeEach(() => {
        vi.resetModules(); // This is key to allow `vi.doMock` to work correctly in each test
        vi.clearAllMocks();
    });

    it('should call a tool and format the final response', async () => {
        // Mock redis for this test
        vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: false,
          redisClient: {},
        }));
        
        // Mock genkit for this test
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
        
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

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
                definePrompt: vi.fn().mockReturnValue(mockPromptFn),
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
        const redisGetMock = vi.fn().mockResolvedValue(JSON.stringify(mockFinalResponse));
        
        vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: true,
          redisClient: {
            get: redisGetMock,
          },
        }));

        vi.doMock('@/ai/genkit', () => ({
          ai: { generate: vi.fn() } // Ensure generate is mocked but won't be called
        }));

        const { universalChatFlow } = await import('@/ai/flows/universal-chat');
        const { ai } = await import('@/ai/genkit');
        
        const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
        const result = await universalChatFlow(input);

        expect(redisGetMock).toHaveBeenCalledWith('aichat:test-company-id:mocked-hash');
        expect(ai.generate).not.toHaveBeenCalled();
        expect(result.response).toBe(mockFinalResponse.response);
    });
    
    it('should handle errors gracefully', async () => {
       vi.doMock('@/lib/redis', () => ({
          isRedisEnabled: false,
          redisClient: {},
        }));

       vi.doMock('@/ai/genkit', () => ({
          ai: {
            defineFlow: vi.fn((_, impl) => impl),
            generate: vi.fn().mockRejectedValue(new Error('Service unavailable')),
          }
       }));

       const { universalChatFlow } = await import('@/ai/flows/universal-chat');
       
       const input = { companyId: mockCompanyId, conversationHistory: mockConversationHistory as Message[] };
       const result = await universalChatFlow(input);

        expect(result.response).toContain('AI service is currently unavailable');
        expect(result.confidence).toBe(0.0);
        expect(result.is_error).toBe(true);
    });
});
