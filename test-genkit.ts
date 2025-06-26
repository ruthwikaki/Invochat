
import { config } from 'dotenv';
config(); // Load environment variables from .env

import {genkit, type Genkit} from 'genkit';
import {googleAI} from '@genkit-ai/googleai';

async function runTest() {
  console.log('--- Genkit Standalone Diagnostic Test ---');

  if (!process.env.GOOGLE_API_KEY) {
    console.error('❌ ERROR: GOOGLE_API_KEY is not set in your .env file.');
    return;
  }
  
  console.log('✅ GOOGLE_API_KEY found.');

  let ai: Genkit;
  try {
    console.log('Initializing Genkit with Google AI plugin...');
    ai = genkit({
      plugins: [googleAI({ apiKey: process.env.GOOGLE_API_KEY })],
    });
    console.log('✅ Genkit initialized successfully.');
  } catch(e: any) {
    console.error('❌ FAILED to initialize Genkit. Error:', e.message);
    return;
  }

  const modelsToTest = [
    'googleai/gemini-1.5-flash-latest',
    'googleai/gemini-1.0-pro',
    'googleai/gemini-pro',
  ];
  let successfulModel = null;

  for (const modelName of modelsToTest) {
    try {
        console.log(`\nAttempting to generate content with model: ${modelName}...`);

        const { output } = await ai.generate({
            model: modelName,
            prompt: 'Tell me a one-sentence joke about inventory management.',
        });
        
        console.log('✅✅✅ SUCCESS! ✅✅✅');
        console.log('AI Response:', output);
        successfulModel = modelName;
        break; // Stop on first success

    } catch (error: any) {
        console.error(`❌ TEST FAILED for model ${modelName}.`);
        console.error('Error Details:', error.message);
    }
  }

  console.log('\n--- Test Complete ---');
  if (successfulModel) {
    console.log(`\nConclusion: Success with model '${successfulModel}'!`);
    console.log('If you ask me to, I can now update the main application to use this working model.');
  } else {
    console.log('\nConclusion: All tested models failed.');
    console.log('This confirms the issue is with your Google Cloud Project setup or API Key.');
    console.log('Possible reasons:');
    console.log('1. The tested models are not available in your project\'s region.');
    console.log('2. Your project is missing a billing account, which is required for this API.');
    console.log('3. The API key does not have permissions for the "Generative Language API".');
    console.log('\nNext Steps:');
    console.log('- Verify your GOOGLE_API_KEY in .env belongs to the project where the "Generative Language API" is enabled.');
    console.log('- Check that a billing account is linked to your Google Cloud project: https://cloud.google.com/billing/docs/how-to/modify-project');
  }
}

runTest();
