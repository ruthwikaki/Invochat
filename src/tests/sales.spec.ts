

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    await expect(page.getByText('Sales Overview')).toBeVisible({ timeout: 20000 });
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

    const tableRows = page.getByTestId('sales-table').locator('tbody tr');
    // Check if there's at least one row, or the "no results" message
    await expect(tableRows.first().or(page.getByText('No sales orders found'))).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    const salesTable = page.getByTestId('sales-table');
    const rows = salesTable.locator('tbody tr');
    
    const firstRowIsVisible = await rows.first().isVisible({ timeout: 5000 }).catch(() => false);
    if (!firstRowIsVisible) {
      test.skip(true, 'No sales rows seeded to test filtering.');
      return;
    }
    
    const firstRowOrderNumberCell = rows.first().locator('td').first();
    const orderNumber = await firstRowOrderNumberCell.textContent();
    expect(orderNumber).toBeDefined();

    await page.getByTestId('sales-search').fill(orderNumber!);
    
    await expect(rows.first()).toContainText(orderNumber!);
    
    await page.getByTestId('sales-search').fill('NONEXISTENT_ORDER_12345');
    await expect(page.getByText('No sales orders found matching your search.')).toBeVisible({ timeout: 10000 });
  });
});
