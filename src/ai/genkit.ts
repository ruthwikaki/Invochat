
import {genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';
import { envValidation } from '@/config/app-config';

// The validation logic is now handled by the root layout, which will
// show a graceful error page instead of crashing the server.
// We can now safely initialize the client here, assuming the .env file is correctly populated.

logger.info('[Genkit] Initializing Genkit with Google AI plugin...');

// Directly export the configured 'ai' instance.
// The Firebase plugin has been removed to resolve the authentication conflict.
export const ai = genkit({
    plugins: [
        googleAI({ apiKey: process.env.GOOGLE_API_KEY })
    ],
});

logger.info('[Genkit] Genkit client initialized successfully.');
