
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Sales Page', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/sales');
  });

  test('should load and display sales analytics and orders table', async ({ page }) => {
    // Check for the main heading
    await expect(page.getByRole('heading', { name: 'Sales History' })).toBeVisible();

    // Check for the statistic cards
    await expect(page.getByRole('heading', { name: 'Total Revenue' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Total Orders' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Average Order Value' })).toBeVisible();

    // Check that the sales table is visible
    const salesTable = page.getByRole('table');
    await expect(salesTable).toBeVisible();

    // Check for at least one row in the table (assuming mock data exists)
    const firstRow = salesTable.locator('tbody > tr').first();
    await expect(firstRow).toBeVisible();
  });

  test('should allow searching for a sale', async ({ page }) => {
    // This test assumes a sale exists with a customer email containing "customer"
    const searchInput = page.getByPlaceholder(/Search by order number or customer email/);
    await searchInput.fill('customer');

    // Wait for network idle to ensure search has processed
    await page.waitForLoadState('networkidle');

    // All visible rows should contain the search term in some capacity
    const rows = await page.locator('table > tbody > tr').all();
    for (const row of rows) {
      const rowText = await row.innerText();
      // This is a broad check; a real test might be more specific
      expect(rowText.toLowerCase()).toContain('customer');
    }
  });

  test('should allow exporting sales data', async ({ page }) => {
    const exportButton = page.getByRole('button', { name: 'Export' });
    const downloadPromise = page.waitForEvent('download');

    await exportButton.click();

    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe('sales_orders.csv');
  });
});
