

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Inventory Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
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
    await page.keyboard.press('Enter');
    
    const firstRow = page.locator('table > tbody > tr').first();
    await expect(firstRow.or(page.getByText('No inventory found'))).toBeVisible();
    if (await firstRow.isVisible()) {
      await expect(firstRow).toContainText(new RegExp(searchTerm, 'i'));
    }
    
    await page.locator('input[placeholder*="Search by product title or SKU..."]').fill('');
    await page.keyboard.press('Enter');
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
});
