import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';

// Ensure the GOOGLE_API_KEY is set, otherwise throw a startup error.
if (!process.env.GOOGLE_API_KEY) {
  throw new Error('FATAL: GOOGLE_API_KEY environment variable is not set.');
}

logger.info('[Genkit] Initializing with Google AI plugin');

// Initialize Genkit with the Google AI plugin.
// The model itself is specified in each `ai.generate()` call.
export const ai = genkit({
  plugins: [
    googleAI({ apiKey: process.env.GOOGLE_API_KEY })
  ],
});

logger.info('[Genkit] Initialized successfully');
