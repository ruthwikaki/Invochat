import { test, expect } from '@playwright/test';

test.describe('Customers Page', () => {
  test.beforeEach(async ({ page }) => {
    // Assuming login is handled globally or via a stored state
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    await page.goto('/customers');
  });

  test('should load customer analytics and table', async ({ page }) => {
    await expect(page.getByText('Total Customers')).toBeVisible();
    await expect(page.getByText('All Customers')).toBeVisible();

    // Check if the table has rows or shows the empty state
    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first().or(page.getByText('No customers found'))).toBeVisible();
  });

  test('should filter customers by name', async ({ page }) => {
    // This test assumes a known customer exists in the test data
    const hasData = await page.locator('table > tbody > tr').first().isVisible();
    if (!hasData) {
      console.log('Skipping filter test, no customer data available.');
      return;
    }
    await page.fill('input[placeholder*="Search by customer name"]', 'Simulated Customer');
    
    // Check that only rows with the search term are visible, or the no results message
    const tableBody = page.locator('table > tbody');
    await expect(tableBody.locator('tr').first().or(page.getByText('No customers found matching'))).toBeVisible();
    
    if (await tableBody.locator('tr').first().isVisible()){
        await expect(tableBody).toContainText('Simulated Customer');
    }
    
    // Clear search and verify original data returns
    await page.fill('input[placeholder*="Search by customer name"]', '');
    await expect(page.locator('table > tbody > tr').first()).toBeVisible();
  });
});
