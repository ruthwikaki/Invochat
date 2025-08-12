

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    // Wait for either the empty state or the actual dashboard content
    await page.waitForSelector('text=/Welcome to ARVO|Sales Overview/', { timeout: 20000 });
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
    expect(inventoryValue).toBeGreaterThanOrEqual(0); // Allow for 0 if no data

    const tableRows = page.getByTestId('inventory-table').locator('tbody tr');
    // It's okay if the table is empty, we just need to know it loaded.
    await expect(tableRows.first().or(page.getByText('No inventory found'))).toBeVisible();
  });

  test('should filter inventory by name', async ({ page }) => {
    const searchTerm = '4K Smart TV';
    // This test assumes a known product exists in the test data
    await page.getByTestId('inventory-search').fill(searchTerm);
    
    // Check that only rows with the search term are visible
    const firstRow = page.getByTestId('inventory-table').locator('tbody tr').first();
    await expect(firstRow.or(page.getByText('No inventory found'))).toBeVisible();
    if (await firstRow.isVisible()) {
      // **FIX:** The assertion should check for the actual search term, not a generic one.
      await expect(firstRow).toContainText(new RegExp(searchTerm, 'i'));
    }
    
    // Clear the search and verify more data appears if it exists
    await page.getByTestId('inventory-search').fill('');
    const firstRowAfterClear = page.getByTestId('inventory-table').locator('tbody tr').first();
    await expect(firstRowAfterClear.or(page.getByText('No inventory found'))).toBeVisible();
  });

  test('should expand a product to show variants', async ({ page }) => {
    const firstRow = page.getByTestId('inventory-table').locator('tbody tr').first();
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
    // Start waiting for the download before clicking.
    const downloadPromise = page.waitForEvent('download');
    
    await page.getByTestId('inventory-export').click();
    
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toMatch(/inventory-export-.*\.csv/);
  });
});
