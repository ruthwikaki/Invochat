import { chromium, FullConfig } from '@playwright/test';

async function globalSetup(_config: FullConfig) {
  console.log('🚀 Starting global setup...');
  
  // Wait for the server to be ready
  const browser = await chromium.launch();
  const page = await browser.newPage();
  
  try {
    // Wait for the app to be ready by checking if login page loads
    console.log('⏳ Waiting for application to be ready...');
    await page.goto('http://localhost:3000/login', { 
      waitUntil: 'networkidle',
      timeout: 60000 
    });
    
    // Check if we can see the login form
    await page.waitForSelector('input[name="email"]', { timeout: 10000 });
    console.log('✅ Application is ready!');
    
  } catch (error) {
    console.error('❌ Failed to verify application readiness:', error);
    throw error;
  } finally {
    await browser.close();
  }
}

export default globalSetup;
