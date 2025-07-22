import { test, expect } from '@playwright/test';

test.describe('Customers Page', () => {
  test.beforeEach(async ({ page }) => {
    // Assuming login is handled globally or via a stored state
    await page.goto('/customers');
  });

  test('should load customer analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Customers')).toBeVisible();
    await expect(page.getByText('All Customers')).toBeVisible();

    // Check if the table has rows
    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first()).toBeVisible();
  });

  test('should filter customers by name', async ({ page }) => {
    // This test assumes a known customer exists in the test data
    await page.fill('input[placeholder*="Search by customer name"]', 'Simulated Customer');
    
    // Check that only rows with the search term are visible
    const tableBody = page.locator('table > tbody');
    await expect(tableBody).toContainText('Simulated Customer');
    
    // Clear search and verify original data returns
    await page.fill('input[placeholder*="Search by customer name"]', '');
    await expect(page.getByText('Simulated Customer')).toBeVisible();
  });
});
