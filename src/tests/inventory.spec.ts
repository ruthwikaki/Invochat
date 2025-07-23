import { test, expect } from '@playwright/test';

test.describe('Inventory Page', () => {
  test.beforeEach(async ({ page }) => {
    // Assuming login is handled globally
    await page.goto('/inventory');
  });

  test('should load inventory analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Inventory Value')).toBeVisible();
    await expect(page.getByText('Total Products')).toBeVisible();

    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first()).toBeVisible();
  });

  test('should filter inventory by name', async ({ page }) => {
    await page.fill('input[placeholder*="Search by product title"]', 'Simulated FBA Product');
    
    // Check that only rows with the search term are visible
    const firstRow = page.locator('table > tbody > tr').first();
    await expect(firstRow).toContainText('Simulated FBA Product');
    
    // Clear the search and verify other data appears
    await page.fill('input[placeholder*="Search by product title"]', '');
    await expect(page.locator('table > tbody > tr').first()).not.toContainText('Simulated FBA Product');
  });

  test('should expand a product to show variants', async ({ page }) => {
    const firstRow = page.locator('table > tbody > tr').first();
    const expandButton = firstRow.locator('button').getByRole('button');
    
    // Check that variants are initially hidden
    const variantTable = page.locator('table table'); // Nested table for variants
    await expect(variantTable).not.toBeVisible();
    
    await expandButton.click();
    
    // Check that the variant table is now visible
    await expect(variantTable).toBeVisible();
    await expect(variantTable.locator('tbody tr').first()).toBeVisible();
  });
});
