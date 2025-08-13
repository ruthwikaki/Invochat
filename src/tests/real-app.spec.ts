import { test, expect } from '@playwright/test';

test.describe('Real App Tests', () => {
  test('Login and check real data', async ({ page }) => {
    // Login
    await page.goto('/login');
    await page.fill('input[name="email"]', 'testowner1@example.com');
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    
    // Wait for dashboard with longer timeout
    await page.waitForURL('/dashboard', { timeout: 30000 });
    
    // Check your real revenue
    await expect(page.getByText('$832,750')).toBeVisible();
    console.log('✅ Dashboard shows real revenue');
    
    // Check inventory
    await page.goto('/inventory');
    const products = await page.locator('table tbody tr').count();
    expect(products).toBeGreaterThan(0);
    console.log(`✅ Found ${products} products`);
    
    // Check customers  
    await page.goto('/customers');
    await expect(page.getByText('georgegary@example.com')).toBeVisible();
    console.log('✅ Customer data loaded');
  });
});