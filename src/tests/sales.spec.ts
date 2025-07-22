import { test, expect } from '@playwright/test';

test.describe('Sales Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/sales');
  });

  test('should load sales analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Revenue')).toBeVisible();
    await expect(page.getByText('Total Orders')).toBeVisible();
    await expect(page.getByText('Average Order Value')).toBeVisible();

    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first()).toBeVisible();
  });

  test('should filter sales by order number', async ({ page }) => {
    await page.fill('input[placeholder*="Search by order number"]', 'ORD-');
    
    const tableBody = page.locator('table > tbody');
    await expect(tableBody).toContainText('ORD-');
    
    await page.fill('input[placeholder*="Search by order number"]', '');
    await expect(tableBody).toContainText('ORD-'); // assuming data doesn't change
  });
});
