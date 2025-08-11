

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 60000 });
    await expect(page.getByTestId('dashboard-root')).toBeVisible({ timeout: 15000 });
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
    expect(revenueValue).toBeGreaterThan(0);

    const tableRows = page.locator('table > tbody > tr');
    // Check if there's at least one row, or the "no results" message
    await expect(tableRows.first().or(page.getByText('No sales orders found'))).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    // This test assumes some data exists. We'll search for a common prefix.
    const hasData = await page.locator('table > tbody > tr').first().isVisible();
    if (!hasData) {
      console.log('Skipping filter test, no sales data available.');
      return;
    }
    
    const salesTable = page.getByTestId('sales-table');
    const firstRowText = await salesTable.locator('tbody tr').first().innerText();
    const inferredOrder = (firstRowText.match(/ORD-\w+-\d+/)?.[0]);
    expect(inferredOrder).toBeDefined();

    await page.getByTestId('sales-search').fill(inferredOrder!.slice(0, 8));
    
    const tableBody = salesTable.locator('tbody');
    await expect(tableBody.locator('tr').first().or(page.getByText('No matching results'))).toBeVisible();
    
    if (await tableBody.locator('tr').first().isVisible()) {
        await expect(tableBody.locator('tr').first()).toContainText(inferredOrder!.slice(0, 8));
    }
    
    await page.getByTestId('sales-search').fill('NONEXISTENT_ORDER_12345');
    await expect(page.getByText('No sales orders found matching your search.')).toBeVisible();
  });
});
