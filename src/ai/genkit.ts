
import {genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';
import { envValidation } from '@/config/app-config';

// This block will now throw a clear error during startup if keys are missing,
// which is better than a lazy-load error deep in a call stack.
if (!envValidation.success || !process.env.GOOGLE_API_KEY) {
    const missingVars = envValidation.success ? ['GOOGLE_API_KEY'] : Object.keys(envValidation.error.flatten().fieldErrors);
    throw new Error(`Genkit initialization failed. Missing required environment variables: ${missingVars.join(', ')}. Please check your .env file.`);
}

logger.info('[Genkit] Initializing Genkit with Google AI plugin...');

// Directly export the configured 'ai' instance.
export const ai = genkit({
    plugins: [
        googleAI({ apiKey: process.env.GOOGLE_API_KEY })
    ],
});

logger.info('[Genkit] Genkit client initialized successfully.');
