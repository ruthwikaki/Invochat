
import {genkit} from 'genkit';
import {googleAI} from '@gen-kit/google-ai';
import { logger } from '@/lib/logger';
import { config } from '@/config/app-config';

logger.info('[Genkit] Initializing Genkit with Google AI plugin...');

export const ai = genkit({
    plugins: [
        googleAI({ apiKey: process.env.GOOGLE_API_KEY })
    ],
});

logger.info('[Genkit] Genkit client initialized successfully.');
