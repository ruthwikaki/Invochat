
import {genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';
import { envValidation } from '@/config/app-config';

// Validate environment variables before initializing Genkit
if (!envValidation.success) {
    const googleApiKeyError = envValidation.error.flatten().fieldErrors.GOOGLE_API_KEY?.[0];
    const errorMessage = `Genkit cannot be initialized: ${googleApiKeyError || 'Required environment variables are missing.'}`;
    logger.error(errorMessage);
    // In a real application, you might throw an error here to prevent startup
    // For this context, we will allow it to proceed but log a critical error.
}

logger.info('[Genkit] Initializing Genkit with Google AI plugin...');

export const ai = genkit({
    plugins: [
        googleAI({ apiKey: process.env.GOOGLE_API_KEY })
    ],
});

logger.info('[Genkit] Genkit client initialized successfully.');

    
