
import { test, expect } from '@playwright/test';

test.describe('Sales Page', () => {
  test.beforeEach(async ({ page }) => {
    // Tests will use shared authentication state
    await page.goto('/sales');
    await page.waitForURL('/sales');
  });

  test('should load sales analytics and validate data', async ({ page }) => {
    // Wait for page to load and scroll to ensure all elements are visible
    await page.waitForLoadState('networkidle');
    
    // Scroll to top to ensure analytics cards are visible
    await page.evaluate(() => window.scrollTo(0, 0));
    
    // Wait for analytics data to load
    await page.waitForTimeout(2000);
    
    await expect(page.getByText('Total Revenue')).toBeVisible();
    await expect(page.getByText('Total Orders')).toBeVisible();
    await expect(page.getByText('Average Order Value')).toBeVisible();

    const totalRevenueCard = page.locator('.card', { hasText: 'Total Revenue' });
    const revenueText = await totalRevenueCard.locator('.text-2xl').innerText({ timeout: 10000 });
    const revenueValue = parseFloat(revenueText.replace(/[^0-9.-]+/g,""));
    expect(revenueValue).toBeGreaterThanOrEqual(0);

    const tableRows = page.getByTestId('sales-table').locator('tbody tr');
    await expect(tableRows.first().or(page.getByText('No sales orders found'))).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    // Wait for page to load and scroll to ensure search input is visible
    await page.waitForLoadState('networkidle');
    await page.waitForTimeout(2000);
    
    // Scroll to the search area
    await page.evaluate(() => {
      const searchInput = document.querySelector('[data-testid="sales-search"]');
      if (searchInput) {
        searchInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
    
    // Wait for search input to be visible and use the test ID
    await expect(page.getByTestId('sales-search')).toBeVisible();
    await page.fill('[data-testid="sales-search"]', 'NONEXISTENT999');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1000);

    const tableRows = await page.locator('table tbody tr').count();
    expect(tableRows).toBe(0);
  });
});

    