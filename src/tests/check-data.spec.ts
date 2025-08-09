// src/tests/check-data.spec.ts
import { test, expect } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0];

test('check what data exists', async ({ page }) => {
  // Login
  await page.goto('/login');
  await page.fill('input[name="email"]', testUser.email);
  await page.fill('input[name="password"]', testUser.password);
  await page.click('button[type="submit"]');
  
  // Wait for dashboard
  await page.waitForURL('/dashboard', { timeout: 30000 });
  
  // Check if empty state is showing
  const emptyState = page.locator('text="Welcome to ARVO!"');
  const hasEmptyState = await emptyState.count() > 0;
  
  if (hasEmptyState) {
    // Dashboard is showing empty state
    await expect(emptyState).toBeVisible();
    throw new Error('Dashboard is showing empty state - no data!');
  }
  
  // Check for dashboard elements
  await expect(page.locator('text="Total Revenue"')).toBeVisible({ timeout: 10000 });
  await expect(page.locator('text="Total Orders"')).toBeVisible();
  await expect(page.locator('text="New Customers"')).toBeVisible();
  
  // Get the actual values
  const revenueCard = page.locator('text="Total Revenue"').locator('..').locator('..');
  const revenueText = await revenueCard.innerText();
  console.log('Revenue Card:', revenueText);
  
  // Take screenshot
  await page.screenshot({ path: 'dashboard-state.png', fullPage: true });
});