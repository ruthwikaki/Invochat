'use server';

/**
 * @fileoverview Genkit service wrapper.
 * This file encapsulates Genkit initialization and provides a test function
 * to verify API connectivity.
 */
import { ai } from '@/ai/genkit';
import { envValidation } from '@/config/app-config';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { withTimeout } from '@/lib/async-utils';

const GENKIT_TEST_TIMEOUT = 10000; // 10 seconds

/**
 * Tests the connection to the underlying Genkit AI service.
 * @returns A promise that resolves to an object indicating connection status.
 */
export async function testGenkitConnection(): Promise<{ isConfigured: boolean; success: boolean; error?: string }> {
  // Use the pre-validated environment status from the config file.
  if (!envValidation.success) {
      const googleApiKeyError = envValidation.error.flatten().fieldErrors.GOOGLE_API_KEY?.[0];
      return {
          isConfigured: false,
          success: false,
          error: `Google AI credentials are not configured: ${googleApiKeyError || 'No error message.'}`,
      };
  }
  
  try {
    const testPromise = ai.generate({
        prompt: "Say 'hello'",
        model: 'googleai/gemini-1.5-flash',
        temperature: 0,
        output: { format: 'text' },
    });

    await withTimeout(
        testPromise,
        GENKIT_TEST_TIMEOUT,
        'Genkit API connection test timed out.'
    );

    return {
      isConfigured: true,
      success: true,
    };
  } catch (e: unknown) {
    logError(e, { context: 'Genkit Connection Test Failed' });
    return {
      isConfigured: true,
      success: false,
      error: getErrorMessage(e),
    };
  }
}
