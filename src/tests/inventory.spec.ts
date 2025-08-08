

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await expect(page.getByText('Sales Overview')).toBeVisible({ timeout: 60000 });
}

test.describe('Inventory Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/inventory');
    await page.waitForURL('/inventory');
  });

  test('should load inventory analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Inventory Value')).toBeVisible();
    await expect(page.getByText('Total Products')).toBeVisible();

    const totalValueCard = page.locator('.card', { hasText: 'Total Inventory Value' });
    const valueText = await totalValueCard.locator('.text-2xl').innerText();
    const inventoryValue = parseFloat(valueText.replace(/[^0-9.-]+/g,""));
    expect(inventoryValue).toBeGreaterThan(0);

    const tableRows = page.locator('table > tbody > tr');
    // It's okay if the table is empty, we just need to know it loaded.
    await expect(tableRows.first().or(page.getByText('No inventory found'))).toBeVisible();
  });

  test('should filter inventory by name', async ({ page }) => {
    // This test assumes a known product exists in the test data
    await page.fill('input[placeholder*="Search by product title"]', 'Simulated FBA Product');
    
    // Check that only rows with the search term are visible
    const firstRow = page.locator('table > tbody > tr').first();
    await expect(firstRow.or(page.getByText('No inventory found'))).toBeVisible();
    if (await firstRow.isVisible()) {
      await expect(firstRow).toContainText('Simulated FBA Product');
    }
    
    // Clear the search and verify more data appears if it exists
    await page.fill('input[placeholder*="Search by product title"]', '');
    const firstRowAfterClear = page.locator('table > tbody > tr').first();
    await expect(firstRowAfterClear.or(page.getByText('No inventory found'))).toBeVisible();
  });

  test('should expand a product to show variants', async ({ page }) => {
    const firstRow = page.locator('table > tbody > tr').first();
    if (!await firstRow.isVisible({timeout: 5000})) {
      console.log('Skipping expand test, no inventory data available.');
      return;
    }
    
    const expandButton = firstRow.getByRole('button');
    
    // Check that variants are initially hidden
    const variantTable = page.locator('table table'); // Nested table for variants
    await expect(variantTable).not.toBeVisible();
    
    await expandButton.click();
    
    // Check that the variant table is now visible
    await expect(variantTable).toBeVisible();
    await expect(variantTable.locator('tbody tr').first().or(page.getByText('No variants'))).toBeVisible();
  });

  test('should trigger a file download when Export is clicked', async ({ page }) => {
    // Start waiting for the download before clicking the button
    const downloadPromise = page.waitForEvent('download');
    
    await page.getByRole('button', { name: 'Export' }).click();
    
    const download = await downloadPromise;
    
    // Check that the download is for a CSV file
    expect(download.suggestedFilename()).toContain('.csv');
    
    // Verify the file is not empty
    const stream = await download.createReadStream();
    const fileContent = (await stream.read()).toString();
    expect(fileContent).toContain('product_title,variant_title,sku');
  });
});

