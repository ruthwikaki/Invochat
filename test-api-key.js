// Test the Google API key directly
require('dotenv').config({ path: '.env.local' });

const { GoogleGenerativeAI } = require('@google/generative-ai');

const apiKey = process.env.GOOGLE_API_KEY;
console.log('Testing API Key:', apiKey ? `${apiKey.substring(0, 10)}...` : 'NOT FOUND');

async function testApiKey() {
  try {
    if (!apiKey) {
      throw new Error('No API key found in environment');
    }

    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

    const result = await model.generateContent('Hello, world!');
    const response = await result.response;
    console.log('✅ API Key is valid! Response:', response.text());
  } catch (error) {
    console.error('❌ API Key test failed:', error.message);
    if (error.message.includes('API Key not found')) {
      console.error('💡 The API key appears to be invalid or malformed');
    }
  }
}

testApiKey();
