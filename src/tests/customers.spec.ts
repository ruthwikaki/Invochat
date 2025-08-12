

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Customers Page', () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
    await page.goto('/customers');
    await page.waitForURL('/customers');
  });

  test('should load customer analytics and validate data', async ({ page }) => {
    await expect(page.getByTestId('total-customers-card')).toBeVisible({ timeout: 10000 });
    await expect(page.getByText('All Customers')).toBeVisible();

    const totalCustomersCard = page.getByTestId('total-customers-card');
    await expect(totalCustomersCard).toBeVisible();

    const customersText = await totalCustomersCard.locator('.text-2xl').innerText();
    const customersValue = parseInt(customersText.replace(/,/g, ''), 10);
    expect(customersValue).toBeGreaterThanOrEqual(0);

    const tableRows = page.locator('table > tbody > tr');
    await expect(tableRows.first().or(page.getByText('No customers found'))).toBeVisible();
  });

  test('should filter customers by name', async ({ page }) => {
    await expect(page.locator('table').first()).toBeVisible({ timeout: 10000 });
    const hasData = await page.locator('table > tbody > tr').first().isVisible({timeout: 5000}).catch(() => false);
    if (!hasData) {
      console.log('Skipping filter test, no customer data available.');
      return;
    }
    await page.fill('input[placeholder*="Search by customer name"]', 'Simulated Customer');
    
    const tableBody = page.locator('table > tbody');
    await expect(tableBody.locator('tr').first().or(page.getByText('No customers found matching'))).toBeVisible();
    
    if (await tableBody.locator('tr').first().isVisible()){
        await expect(tableBody).toContainText('Simulated Customer');
    }
    
    await page.fill('input[placeholder*="Search by customer name"]', '');
    await expect(page.locator('table > tbody > tr').first()).toBeVisible();
  });
});
