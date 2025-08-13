import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ai } from '../../ai/genkit';
import { testGenkitConnection } from '../../services/genkit';
import { envValidation } from '../../config/app-config';

// Mock the AI module
vi.mock('../../ai/genkit', () => ({
  ai: {
    generate: vi.fn(),
  },
}));

// Mock the config
vi.mock('../../config/app-config', () => ({
    envValidation: { success: true, data: {} },
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
    vi.spyOn(envValidation, 'success', 'get').mockReturnValue(false);
    vi.spyOn(envValidation, 'error', 'get').mockReturnValue({ flatten: () => ({ fieldErrors: { GOOGLE_API_KEY: ['Is not set.'] } }) } as any);

    const result = await testGenkitConnection();
    expect(result.success).toBe(false);
    expect(result.isConfigured).toBe(false);
    expect(result.error).toContain('Google AI credentials are not configured');
    
    // Restore mock
    vi.spyOn(envValidation, 'success', 'get').mockReturnValue(true);
  });
});



