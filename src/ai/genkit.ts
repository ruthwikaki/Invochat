
import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';

let aiInstance: Genkit | null = null;

/**
 * Returns a lazily initialized Genkit AI client instance.
 * This prevents the application from crashing on startup if the GOOGLE_API_KEY
 * environment variable is missing.
 *
 * @throws {Error} If the GOOGLE_API_KEY is not set when the client is accessed.
 */
export function getAiClient(): Genkit {
    if (aiInstance) {
        return aiInstance;
    }

    const apiKey = process.env.GOOGLE_API_KEY;
    if (!apiKey) {
        // This error will be caught by error boundaries in the app, preventing a crash.
        throw new Error('Genkit client is not configured. The GOOGLE_API_KEY environment variable is missing.');
    }

    logger.info('[Genkit] Lazily initializing Genkit with Google AI plugin');

    aiInstance = genkit({
        plugins: [
            googleAI({ apiKey: apiKey })
        ],
    });

    logger.info('[Genkit] Genkit client initialized successfully');
    return aiInstance;
}
