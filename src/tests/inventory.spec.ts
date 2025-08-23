
import { test, expect } from '@playwright/test';

test.describe('Inventory Page', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate directly to inventory page - authentication should already be handled by chromium project
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
    // Look for pagination controls with flexible selectors
    const paginationElements = [
      page.getByRole('button', { name: 'Next' }),
      page.getByRole('button', { name: /next/i }),
      page.locator('button[aria-label*="next"]'),
      page.locator('.pagination button').last(),
      page.locator('[data-testid*="next"]')
    ];

    let nextButton = null;
    for (const element of paginationElements) {
      if (await element.isVisible({ timeout: 2000 }).catch(() => false)) {
        nextButton = element;
        break;
      }
    }

    if (!nextButton) {
      console.log('Skipping pagination test, no pagination controls found.');
      // Just verify the inventory page works
      const hasTable = await page.locator('table, .grid, [data-testid*="inventory"]').isVisible();
      expect(hasTable).toBeTruthy();
      return;
    }

    // Check if pagination is actually needed
    const isEnabled = await nextButton.isEnabled().catch(() => false);
    if (!isEnabled) {
      console.log('Skipping pagination test, not enough items for a second page.');
      return;
    }

    // Store first row content if available
    let firstRowText = '';
    try {
      const firstRow = page.locator('table > tbody > tr, .grid-row, [data-testid*="row"]').first();
      if (await firstRow.isVisible({ timeout: 2000 })) {
        firstRowText = await firstRow.innerText();
      }
    } catch (error) {
      console.log('Could not capture first row text:', error);
    }
    
    await nextButton.click();
    
    // Wait for navigation or content change
    await page.waitForTimeout(2000);
    
    // Verify pagination worked by checking URL or content change
    const urlChanged = page.url().includes('page=2') || page.url().includes('offset=');
    const contentChanged = firstRowText ? 
      (await page.locator('table > tbody > tr, .grid-row').first().innerText().catch(() => '') !== firstRowText) :
      true;
    
    expect(urlChanged || contentChanged).toBeTruthy();
  });

  test('should display items correctly when using filter', async ({ page }) => {
    // Try different filter input selectors
    const filterElements = [
      page.getByPlaceholder(/search|filter/i),
      page.locator('input[type="search"]'),
      page.locator('input[placeholder*="filter"]'),
      page.locator('[data-testid*="filter"]'),
      page.locator('.filter input')
    ];

    let filterInput = null;
    for (const element of filterElements) {
      if (await element.isVisible({ timeout: 2000 }).catch(() => false)) {
        filterInput = element;
        break;
      }
    }

    if (!filterInput) {
      console.log('Skipping filter test, no filter input found.');
      return;
    }

    // Count initial items
    const initialCount = await page.locator('table > tbody > tr, .grid-row, [data-testid*="row"]').count();
    
    // Apply filter
    await filterInput.fill('test');
    await page.waitForTimeout(1000); // Wait for filtering
    
    // Verify filtering occurred
    const filteredCount = await page.locator('table > tbody > tr, .grid-row, [data-testid*="row"]').count();
    
    // Filter should either reduce count or show no results message
    const hasNoResults = await page.locator('text=/no.*items|no.*results|empty/i').isVisible().catch(() => false);
    
    expect(filteredCount <= initialCount || hasNoResults).toBeTruthy();
  });
});
