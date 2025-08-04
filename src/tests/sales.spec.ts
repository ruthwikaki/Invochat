import { test, expect } from '@playwright/test';

test.describe('Sales Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    await page.goto('/sales');
  });

  test('should load sales analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Revenue')).toBeVisible();
    await expect(page.getByText('Total Orders')).toBeVisible();
    await expect(page.getByText('Average Order Value')).toBeVisible();

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

    await page.fill('input[placeholder*="Search by order number"]', 'FBA-SIM-ORD');
    
    const tableBody = page.locator('table > tbody');
    await expect(tableBody.locator('tr').first()).toContainText('FBA-SIM-ORD');
    
    await page.fill('input[placeholder*="Search by order number"]', 'NONEXISTENT_ORDER_12345');
    await expect(page.getByText('No sales orders found matching your search.')).toBeVisible();
  });
});
