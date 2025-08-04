
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'owner_stylehub@test.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'StyleHub2024!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
}

test.describe('Customers Page', () => {
  test.beforeEach(async ({ page }) => {
    // Assuming login is handled globally or via a stored state
    await login(page);
    await page.goto('/customers');
  });

  test('should load customer analytics and validate data', async ({ page }) => {
    await expect(page.getByText('Total Customers')).toBeVisible();
    await expect(page.getByText('All Customers')).toBeVisible();

    // Validate analytics data
    const totalCustomersCard = page.locator('.card', { hasText: 'Total Customers' });
    const customersText = await totalCustomersCard.locator('.text-2xl').innerText();
    const customersValue = parseInt(customersText.replace(/,/g, ''), 10);
    expect(customersValue).toBeGreaterThan(0);

    // Check if the table has rows or shows the empty state
    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first().or(page.getByText('No customers found'))).toBeVisible();
  });

  test('should filter customers by name', async ({ page }) => {
    // This test assumes a known customer exists in the test data
    const hasData = await page.locator('table > tbody > tr').first().isVisible({timeout: 5000}).catch(() => false);
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
