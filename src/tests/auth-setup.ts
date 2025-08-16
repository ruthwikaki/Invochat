import { test as setup, expect } from '@playwright/test';
import path from 'path';

const authFile = path.join(__dirname, '../../playwright/.auth/user.json');

setup('authenticate', async ({ page }) => {
  console.log('🔐 Setting up shared authentication...');
  
  try {
    await page.goto('/login', { waitUntil: 'networkidle', timeout: 60000 });
    
    // Wait for login form to be ready
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    
    // Perform login
    await page.fill('input[name="email"]', 'testowner1@example.com');
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    
    // Wait for successful login and redirect
    await page.waitForURL('/dashboard', { timeout: 45000 });
    await expect(page.locator('body')).toContainText('Dashboard'); // Or any dashboard-specific element
    
    console.log('✅ Authentication setup complete');
    
    // Save authentication state
    await page.context().storageState({ path: authFile });
  } catch (error) {
    console.error('❌ Authentication setup failed:', error);
    throw error;
  }
});
