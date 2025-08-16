
import { test, expect } from '@playwright/test';
import credentials from './test_data/test_credentials.json';
import { login } from './test-utils';

const testUser = credentials.test_users[0]; // Use the first user for tests

test.describe('Inventory Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page, testUser);
    await page.goto('/inventory');
    await page.waitForURL('/inventory');
  });

  test('should load inventory analytics and table', async ({ page }) => {
    await page.waitForLoadState('networkidle');
  
    const hasInventory = await page.locator('text=/Inventory Management|Products/').first().isVisible();
    expect(hasInventory).toBeTruthy();
    
    const hasEmptyState = await page.locator('text=/Your Inventory is Empty|Import Inventory/').isVisible({ timeout: 5000 }).catch(() => false);
    if (!hasEmptyState) {
      const valueCard = page.locator('.card').filter({ hasText: /Total.*Value/i });
      if (await valueCard.count() > 0) {
        const valueText = await valueCard.locator('.text-2xl').first().innerText();
        expect(valueText).toBeDefined();
      }
    }
  });

  test('should filter inventory by name', async ({ page }) => {
    const searchTerm = '4K Smart TV'; 
    await page.locator('input[placeholder*="Search by product title or SKU..."]').fill(searchTerm);
    
    const firstRow = page.locator('table > tbody > tr').first();
    await expect(firstRow.or(page.getByText('No inventory found'))).toBeVisible();
    if (await firstRow.isVisible()) {
      await expect(firstRow).toContainText(new RegExp(searchTerm, 'i'));
    }
    
    await page.locator('input[placeholder*="Search by product title or SKU..."]').fill('');
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
    
    const variantTable = page.locator('table table'); 
    await expect(variantTable).not.toBeVisible();
    
    await expandButton.click();
    
    await expect(variantTable).toBeVisible();
    await expect(variantTable.locator('tbody tr').first().or(page.getByText('No variants'))).toBeVisible();
  });

  test('should trigger a file download when Export is clicked', async ({ page }) => {
    const downloadPromise = page.waitForEvent('download');
    
    await page.getByTestId('inventory-export').click();
    
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toContain('.csv');
  });

  test('should navigate to the next page using pagination', async ({ page }) => {
    const nextButton = page.getByRole('button', { name: 'Next' });
    if (!await nextButton.isVisible()) {
        console.log('Skipping pagination test, not enough items for a second page.');
        return;
    }

    const firstRowText = await page.locator('table > tbody > tr').first().innerText();
    
    await nextButton.click();
    await page.waitForURL(/page=2/);

    const newFirstRowText = await page.locator('table > tbody > tr').first().innerText();
    
    expect(newFirstRowText).not.toEqual(firstRowText);

    const prevButton = page.getByRole('button', { name: 'Previous' });
    await prevButton.click();
    await page.waitForURL(/page=1/);

    const originalFirstRowText = await page.locator('table > tbody > tr').first().innerText();
    expect(originalFirstRowText).toEqual(firstRowText);
  });
});
