
import { test, expect } from '@playwright/test';

test.describe('Sales Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    await page.goto('/sales');
  });

  test('should load sales analytics and validate data', async ({ page }) => {
    await expect(page.getByText('Total Revenue')).toBeVisible();
    await expect(page.getByText('Total Orders')).toBeVisible();
    await expect(page.getByText('Average Order Value')).toBeVisible();

    // Validate data in analytics cards
    const totalRevenueCard = page.locator('.card', { hasText: 'Total Revenue' });
    const revenueText = await totalRevenueCard.locator('.text-2xl').innerText();
    const revenueValue = parseFloat(revenueText.replace(/[^0-9.-]+/g,""));
    expect(revenueValue).toBeGreaterThan(0);

    const tableRows = page.locator('table > tbody > tr');
    // Check if there's at least one row, or the "no results" message
    await expect(tableRows.first().or(page.getByText('No sales orders found'))).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    // This test assumes some data exists. We'll search for a common prefix.
    const hasData = await page.locator('table > tbody > tr').first().isVisible();
    if (!hasData) {
      console.log('Skipping filter test, no sales data available.');
      return;
    }

    await page.fill('input[placeholder*="Search by order number"]', 'FBA-SIM-ORD');
    
    const tableBody = page.locator('table > tbody');
    await expect(tableBody.locator('tr').first().or(page.getByText('No matching results'))).toBeVisible();
    
    if (await tableBody.locator('tr').first().isVisible()) {
        await expect(tableBody.locator('tr').first()).toContainText('FBA-SIM-ORD');
    }
    
    await page.fill('input[placeholder*="Search by order number"]', 'NONEXISTENT_ORDER_12345');
    await expect(page.getByText('No sales orders found matching your search.')).toBeVisible();
  });
});
