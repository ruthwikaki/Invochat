
import { config } from 'dotenv';
config(); // Load environment variables from .env

import { genkit, type Genkit } from 'genkit';
import { googleAI } from '@genkit-ai/googleai';

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

  const modelName = 'googleai/gemini-1.5-flash-latest';
  try {
    console.log(`Attempting to generate content with model: ${modelName}...`);

    const { output } = await ai.generate({
      model: modelName,
      prompt: 'Tell me a one-sentence joke about inventory management.',
    });

    console.log('✅✅✅ SUCCESS! ✅✅✅');
    console.log('AI Response:', output);
    console.log('\nConclusion: Your API key and project configuration are working correctly with this model.');
    console.log('If this test passes, we can update the main application to use this model.');


  } catch (error: any) {
    console.error('❌❌❌ TEST FAILED ❌❌❌');
    console.error('Error Details:', error.message);
    
    if (error.message?.includes('404') || error.message?.includes('Not Found')) {
        console.log('\nRoot Cause: The "Model not found" error persists even in isolation. This strongly confirms the issue is with your Google Cloud Project setup or API Key.');
        console.log('Possible reasons:');
        console.log('1. The model is not available in your project\'s region.');
        console.log('2. Your project is missing a billing account, which is required for this API.');
        console.log('3. The API key does not have permissions for the Generative Language API.');
        console.log('\nNext Steps:');
        console.log('- Verify your GOOGLE_API_KEY in .env belongs to the project where the "Generative Language API" is enabled.');
        console.log('- Check that a billing account is linked to your Google Cloud project: https://cloud.google.com/billing/docs/how-to/modify-project');
    } else {
        console.log('\nAn unexpected error occurred:', error);
    }
  }
  console.log('--- Test Complete ---');
}

runTest();
