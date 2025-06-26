
import { config } from 'dotenv';
config(); // Load environment variables from .env

async function runTest() {
  console.log('--- Google AI Model Availability Test ---');

  const apiKey = process.env.GOOGLE_API_KEY;

  if (!apiKey) {
    console.error('❌ ERROR: GOOGLE_API_KEY is not set in your .env file.');
    return;
  }
  
  console.log('✅ GOOGLE_API_KEY found. Querying available models from Google...');

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`
    );

    if (!response.ok) {
        const errorBody = await response.json();
        console.error(`❌ FAILED to list models. Status: ${response.status}`);
        console.error('Error Response:', JSON.stringify(errorBody, null, 2));
        console.log('\n--- Troubleshooting ---');
        console.log('This failure indicates a fundamental issue with your Google Cloud Project or API Key.');
        console.log('1. Double-check that your GOOGLE_API_KEY in the .env file is correct and has no extra spaces.');
        console.log('2. Ensure the "Generative Language API" is enabled in the correct Google Cloud project.');
        console.log('3. Confirm a valid billing account is linked to that project.');
        return;
    }

    const data = await response.json();

    if (!data.models || data.models.length === 0) {
        console.log('🟡 No models were returned for your API key.');
        console.log('This is highly unusual and points to a project configuration issue.');
        console.log('Please verify your project setup again (API enabled, billing active).');
        return;
    }
    
    console.log('\n✅ SUCCESS! Found the following models available for your API key:');
    
    const supportedModels = data.models.filter((model: any) => 
        model.supportedGenerationMethods.includes('generateContent')
    );

    if (supportedModels.length === 0) {
        console.log('🟡 Found models, but none of them support the `generateContent` method used by the application.');
        console.log('Full list of discovered models:');
        data.models.forEach((model: any) => console.log(`- ${model.name} (Supports: ${model.supportedGenerationMethods.join(', ')})`));
        return;
    }

    console.log('\n--- Recommended Models to Use ---');
    supportedModels.forEach((model: any) => {
        console.log(`- ${model.displayName} (ID: ${model.name})`);
    });
    
    const bestModel =
      supportedModels.find((m: any) => m.name === 'models/gemini-1.5-flash-latest') ||
      supportedModels.find((m: any) => m.name === 'models/gemini-pro') ||
      supportedModels.find((m: any) => m.name === 'models/gemini-1.0-pro') ||
      supportedModels[0];

    console.log(`\nBased on this list, the best model for your project is '${bestModel.name}'.`);
    console.log('If you ask me to, I will update the application to use this model.');

  } catch (error: any) {
    console.error('\n❌ An unexpected network error occurred:', error.message);
  }
}

runTest();
