
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Customers Page', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/customers');
  });

  test('should load and display customer analytics and table', async ({ page }) => {
    // Check for the main heading
    await expect(page.getByRole('heading', { name: 'Customers' })).toBeVisible();

    // Check for the statistic cards
    await expect(page.getByText('Total Customers')).toBeVisible();
    await expect(page.getByText('Avg. Lifetime Value')).toBeVisible();
    await expect(page.getByText('New Customers (30d)')).toBeVisible();
    await expect(page.getByText('Repeat Customer Rate')).toBeVisible();

    // Check for the top customer lists
    await expect(page.getByRole('heading', { name: 'Top Customers by Spend' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Top Customers by Sales' })).toBeVisible();

    // Check that the main customer table is visible
    const customerTable = page.getByRole('table').last(); // Get the main table, not the ones in the lists
    await expect(customerTable).toBeVisible();

    // Check for at least one row in the table
    const firstRow = customerTable.locator('tbody > tr').first();
    await expect(firstRow).toBeVisible();
  });

  test('should allow searching for a customer', async ({ page }) => {
    // This test assumes a customer with "Simulated" in their name exists
    const searchInput = page.getByPlaceholder(/Search by customer name or email/);
    await searchInput.fill('Simulated');

    await page.waitForLoadState('networkidle');

    const rows = await page.locator('table').last().locator('tbody > tr').all();
    for (const row of rows) {
      await expect(row).toContainText(/Simulated/i);
    }
  });

  test('should allow exporting customer data', async ({ page }) => {
    const exportButton = page.getByRole('button', { name: 'Export' });
    const downloadPromise = page.waitForEvent('download');
    
    await exportButton.click();
    
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe('customers.csv');
  });
});
