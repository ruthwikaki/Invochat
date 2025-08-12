

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Sales Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/sales');
    await page.waitForURL('/sales');
  });

  test('should load sales analytics and validate data', async ({ page }) => {
    await expect(page.getByText('Total Revenue')).toBeVisible();
    await expect(page.getByText('Total Orders')).toBeVisible();
    await expect(page.getByText('Average Order Value')).toBeVisible();

    // Validate data in analytics cards
    const totalRevenueCard = page.locator('.card', { hasText: 'Total Revenue' });
    const revenueText = await totalRevenueCard.locator('.text-2xl').innerText();
    const revenueValue = parseFloat(revenueText.replace(/[^0-9.-]+/g,""));
    expect(revenueValue).toBeGreaterThanOrEqual(0);

    const tableRows = page.getByTestId('sales-table').locator('tbody tr');
    // Check if there's at least one row, or the "no results" message
    await expect(tableRows.first().or(page.getByText('No sales orders found'))).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    await page.goto('/sales');
    await page.waitForLoadState('networkidle');
    
    const searchInput = page.locator('input[placeholder*="Search"], input[type="search"]').first();
    await searchInput.fill('NONEXISTENT_ORDER_12345');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1000);
    
    // Look for any indication of no results
    const noResults = await page.locator('text=/No.*found|No.*results|No.*data|Empty/i').isVisible();
    expect(noResults).toBeTruthy();
  });
});
