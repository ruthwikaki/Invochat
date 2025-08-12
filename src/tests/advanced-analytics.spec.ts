
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

// Helper to parse currency string to number
function parseCurrency(currencyString: string | null): number {
    if (!currencyString) return 0;
    return parseFloat(currencyString.replace(/[^0-9.-]+/g, ''));
}


test.describe('Advanced Analytics Reports Validation', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/analytics/advanced-reports');
  });

  test.skip('ABC Analysis should be logically correct', async ({ page }) => {
    await page.getByRole('tab', { name: 'ABC Analysis' }).click();
    await expect(page.getByText('ABC Analysis Report')).toBeVisible({ timeout: 10000 });

    const tableRows = page.locator('table > tbody > tr');
    const rowCount = await tableRows.count();
    
    if (rowCount === 0) {
      console.warn('⚠️ No data for ABC Analysis. Test is trivially passing.');
      await expect(page.getByText('No ABC Analysis Data')).toBeVisible();
      return;
    }

    let previousRevenue = Infinity;
    let previousCategory = 'A';

    for (let i = 0; i < Math.min(rowCount, 10); i++) { // Check first 10 rows
      const row = tableRows.nth(i);
      const category = await row.locator('td').nth(1).textContent();
      const revenueText = await row.locator('td').nth(2).textContent();
      const revenue = parseCurrency(revenueText);

      // Category should be in order A -> B -> C
      expect(['A', 'B', 'C']).toContain(category!);
      expect(category! >= previousCategory).toBeTruthy();
      
      // Revenue should be descending
      expect(revenue <= previousRevenue).toBeTruthy();

      previousCategory = category!;
      previousRevenue = revenue;
    }
    
    // Check that the last item's cumulative percentage is close to 100
    const lastRow = tableRows.last();
    const cumulativeText = await lastRow.locator('td').nth(3).textContent();
    const cumulativeValue = parseFloat(cumulativeText!.replace('%', ''));
    expect(cumulativeValue).toBeGreaterThan(95);
    expect(cumulativeValue).toBeLessThanOrEqual(101); // Allow for small rounding variance
  });
  
  test.skip('Gross Margin report summary should be arithmetically correct', async ({ page }) => {
    await page.getByRole('tab', { name: 'Gross Margin' }).click();
    await expect(page.getByText('Gross Margin Report')).toBeVisible({ timeout: 10000 });
    
    const hasData = await page.locator('table > tbody > tr').first().isVisible({ timeout: 5000 }).catch(() => false);
    if (!hasData) {
      console.warn('⚠️ No data for Gross Margin report. Test is trivially passing.');
      await expect(page.getByText('No Gross Margin Data')).toBeVisible();
      return;
    }

    // Get summary card values
    const totalRevenue = parseCurrency(await page.getByText('Total Revenue').locator('..').locator('.text-xl').textContent());
    const totalCogs = parseCurrency(await page.getByText('Total COGS').locator('..').locator('.text-xl').textContent());
    const grossMargin = parseCurrency(await page.getByText('Gross Margin').locator('..').locator('.text-xl').textContent());
    
    // Validate the basic calculation
    expect(totalRevenue - totalCogs).toBeCloseTo(grossMargin, 0.01);
  });

});

