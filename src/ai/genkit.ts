import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import type {GenkitPlugin} from 'genkit/plugin';

const plugins: GenkitPlugin[] = [];
let genkitInstance: Genkit;

if (process.env.GOOGLE_API_KEY) {
  plugins.push(googleAI({apiKey: process.env.GOOGLE_API_KEY}));
  genkitInstance = genkit({
    plugins,
    // Note: The model will only be available if the googleAI() plugin is loaded.
    model: 'googleai/gemini-2.0-flash',
  });
} else {
  console.warn(
    `[Genkit] GOOGLE_API_KEY is not set in the environment. AI features will not be available.`
  );
  // Create a stub implementation of Genkit that throws an error when used.
  const unconfiguredError = () => {
    throw new Error('Genkit is not configured. Please set the GOOGLE_API_KEY environment variable.');
  };
  genkitInstance = {
    defineFlow: () => unconfiguredError,
    definePrompt: () => unconfiguredError,
    defineTool: () => unconfiguredError,
    generate: unconfiguredError,
  } as unknown as Genkit;
}

export const ai = genkitInstance;
