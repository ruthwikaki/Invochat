import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import type {GenkitPlugin} from 'genkit/plugin';

const plugins: GenkitPlugin[] = [];
let genkitInstance: Genkit;

if (process.env.GOOGLE_API_KEY) {
  console.log('[Genkit] Initializing with Google AI plugin');
  plugins.push(googleAI({apiKey: process.env.GOOGLE_API_KEY}));
  genkitInstance = genkit({
    plugins,
    // Note: The model will only be available if the googleAI() plugin is loaded.
    model: 'googleai/gemini-1.5-flash',
  });
  console.log('[Genkit] Initialized successfully');
} else {
  console.warn('[Genkit] GOOGLE_API_KEY is not set. AI features will not work.');
  // Create a stub implementation of Genkit that throws an error when used.
  const createError = (method: string) => {
    return () => {
      throw new Error(`Genkit ${method} called but GOOGLE_API_KEY is not set in environment variables`);
    };
  };
  genkitInstance = {
    defineFlow: createError('defineFlow'),
    definePrompt: createError('definePrompt'),
    defineTool: createError('defineTool'),
    generate: createError('generate'),
  } as unknown as Genkit;
}

export const ai = genkitInstance;
