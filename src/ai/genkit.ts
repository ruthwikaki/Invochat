import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import { logger } from '@/lib/logger';

// Startup validation is now handled centrally in src/config/app-config.ts.
// This ensures all necessary environment variables (like GOOGLE_API_KEY)
// are checked in one place before the application starts.

logger.info('[Genkit] Initializing with Google AI plugin');

// Initialize Genkit with the Google AI plugin.
// The model itself is specified in each `ai.generate()` call.
export const ai = genkit({
  plugins: [
    googleAI({ apiKey: process.env.GOOGLE_API_KEY })
  ],
});

logger.info('[Genkit] Initialized successfully');
