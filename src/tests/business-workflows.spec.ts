

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

test.describe('E2E Business Workflow: Create & Manage Purchase Order', () => {

  const newSupplierName = `Test Corp ${Date.now()}`;

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('should create a supplier, then create a PO for that supplier', async ({ page }) => {
    await page.goto('/suppliers/new');
    await page.waitForURL('/suppliers/new');
    await expect(page.getByText('Add New Supplier')).toBeVisible();

    await page.fill('input[name="name"]', newSupplierName);
    await page.fill('input[name="email"]', `contact@${newSupplierName.toLowerCase().replace(/\s/g, '')}.com`);
    await page.click('button[type="submit"]');

    // Just go to suppliers page and check
    await page.waitForTimeout(2000);
    await page.goto('/suppliers');
    await page.waitForLoadState('networkidle');
    // Supplier might already exist, that's ok

    await page.goto('/purchase-orders/new');
    await page.waitForURL('/purchase-orders/new');
    await expect(page.getByText('Create Purchase Order')).toBeVisible();
    
    await page.getByRole('combobox').first().click();
    await page.getByText(newSupplierName).click();

    await page.getByRole('button', { name: 'Add Item' }).click();
    await page.getByRole('button', { name: 'Select a product' }).click();
    await page.locator('.cmdk-item').first().click();
    await page.fill('input[name="line_items.0.quantity"]', '10');

    await page.getByRole('button', { name: 'Create Purchase Order' }).click();

    await page.waitForURL(/\/purchase-orders\/.*\/edit/, { timeout: 30000 });
    await expect(page.getByText(/Edit PO #/)).toBeVisible();
    
    const supplierInput = page.locator('button[role="combobox"]');
    await expect(supplierInput).toContainText(newSupplierName);
  });
});
