
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Inventory Page', () => {
  
  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/inventory');
  });

  test('should display inventory page with products', async ({ page }) => {
    await expect(page.getByRole('heading', { name: 'Inventory Management' })).toBeVisible();

    // Assuming there's at least one product row in the table
    const productRow = page.locator('table > tbody > tr').first();
    await expect(productRow).toBeVisible();
  });

  test('should allow searching for a product', async ({ page }) => {
    // This test assumes a product with "Simulated" in its name exists from the mock data
    const searchInput = page.getByPlaceholder(/Search by product title or SKU/);
    await searchInput.fill('Simulated');

    // Wait for the search to execute (or add a small delay if needed)
    await page.waitForTimeout(500); 

    // All visible rows should contain the search term
    const rows = await page.locator('table > tbody > tr').all();
    for (const row of rows) {
      await expect(row).toContainText(/Simulated/i);
    }
  });

  test('should expand a product to show variants', async ({ page }) => {
    // Find the expand button on the first product row and click it
    const firstRow = page.locator('table > tbody > tr').first();
    const expandButton = firstRow.getByRole('button');
    await expandButton.click();

    // A new row with a nested table for variants should become visible
    const variantTable = page.locator('table > tbody > tr').nth(1).locator('table');
    await expect(variantTable).toBeVisible();

    // The variant table should have headers
    await expect(variantTable.getByRole('columnheader', { name: 'Variant' })).toBeVisible();
    await expect(variantTable.getByRole('columnheader', { name: 'SKU' })).toBeVisible();
    await expect(variantTable.getByRole('columnheader', { name: 'Quantity' })).toBeVisible();
  });

  test('should show a "no results" message for an unfindable search term', async ({ page }) => {
    const searchInput = page.getByPlaceholder(/Search by product title or SKU/);
    await searchInput.fill('nonexistent-product-xyz123');

    // Wait for the search to process
    await page.waitForTimeout(500);

    // The "no results" message should be visible in the table
    const noResultsMessage = page.getByText('No inventory found matching your criteria.');
    await expect(noResultsMessage).toBeVisible();

    // Make sure there are no actual product rows visible
    const productRows = page.locator('table > tbody > tr > td:has-text("Simulated")');
    await expect(productRows).toHaveCount(0);
  });

  test('should allow exporting data to CSV', async ({ page }) => {
    const exportButton = page.getByRole('button', { name: 'Export' });
    
    // Start waiting for the download before clicking the button.
    const downloadPromise = page.waitForEvent('download');
    
    await exportButton.click();
    
    const download = await downloadPromise;

    // Verify the download.
    expect(download.suggestedFilename()).toBe('inventory.csv');
    
    // Optional: check file size to ensure it's not empty
    const size = await download.size();
    expect(size).toBeGreaterThan(0);
  });
});
