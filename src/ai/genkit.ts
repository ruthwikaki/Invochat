import {genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';
import type {GenkitPlugin} from 'genkit/plugin';

const plugins: GenkitPlugin[] = [];

if (process.env.GOOGLE_API_KEY) {
  plugins.push(googleAI());
} else {
  console.warn(
    `[Genkit] GOOGLE_API_KEY is not set in the environment. AI features may not be available.`
  );
}

export const ai = genkit({
  plugins,
  // Note: The model will only be available if the googleAI() plugin is loaded.
  model: 'googleai/gemini-2.0-flash',
});
