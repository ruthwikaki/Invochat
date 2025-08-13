
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ai } from '@/ai/genkit';
import { testGenkitConnection } from '@/services/genkit';
import { envValidation } from '@/config/app-config';
import { config } from '@/config/app-config';

// Mock the AI module
vi.mock('@/ai/genkit', () => ({
  ai: {
    generate: vi.fn(),
  },
}));

// Mock the config
vi.mock('@/config/app-config', () => ({
    envValidation: { success: true, data: { GOOGLE_API_KEY: 'test-key' } },
    config: {
        ai: {
            model: 'googleai/gemini-1.5-flash',
            maxOutputTokens: 2048,
        },
    },
}));

describe('testGenkitConnection', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should return success if AI generation works', async () => {
    (ai.generate as any).mockResolvedValue({ text: 'hello' });
    const result = await testGenkitConnection();
    expect(result.success).toBe(true);
    expect(result.isConfigured).toBe(true);
  });

  it('should return failure if AI generation throws an error', async () => {
    const error = new Error('API Key Invalid');
    (ai.generate as any).mockRejectedValue(error);
    const result = await testGenkitConnection();
    expect(result.success).toBe(false);
    expect(result.isConfigured).toBe(true);
    expect(result.error).toBe('API Key Invalid');
  });

  it('should return failure if environment variables are not configured', async () => {
    // Temporarily mock envValidation to be unsuccessful
    const originalSuccess = envValidation.success;
    const originalError = (envValidation as any).error;
    (envValidation as any).success = false;
    (envValidation as any).error = { flatten: () => ({ fieldErrors: { GOOGLE_API_KEY: ['Is not set.'] } }) };

    const result = await testGenkitConnection();
    expect(result.success).toBe(false);
    expect(result.isConfigured).toBe(false);
    expect(result.error).toContain('Google AI credentials are not configured');

    // Restore mock
    (envValidation as any).success = originalSuccess;
    (envValidation as any).error = originalError;
  });
});
