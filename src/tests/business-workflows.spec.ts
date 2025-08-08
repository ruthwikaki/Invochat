

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

// This E2E test simulates a full "Day in the Life" workflow for a user.
// It combines multiple features to ensure they work together seamlessly.

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    // Wait for a specific element that indicates the dashboard is fully loaded
    await expect(page.getByText('Sales Overview')).toBeVisible({ timeout: 60000 });
}

test.describe('E2E Business Workflow: Create & Manage Purchase Order', () => {

  const newSupplierName = `Test Corp ${Date.now()}`;

  test.beforeEach(async ({ page }) => {
    // Start by logging in
    await login(page);
  });

  test('should create a supplier, then create a PO for that supplier', async ({ page }) => {
    // 1. Create a new supplier
    await page.goto('/suppliers/new');
    await page.waitForURL('/suppliers/new');
    await expect(page.getByText('Add New Supplier')).toBeVisible();

    await page.fill('input[name="name"]', newSupplierName);
    await page.fill('input[name="email"]', `contact@${newSupplierName.toLowerCase().replace(/\s/g, '')}.com`);
    await page.click('button[type="submit"]');

    // 2. Verify the supplier was created and is in the list
    await page.waitForURL('/suppliers');
    await expect(page.getByText(newSupplierName)).toBeVisible();

    // 3. Navigate to create a new purchase order
    await page.goto('/purchase-orders/new');
    await page.waitForURL('/purchase-orders/new');
    await expect(page.getByText('Create Purchase Order')).toBeVisible();
    
    // 4. Select the newly created supplier
    await page.getByRole('combobox').first().click();
    await page.getByText(newSupplierName).click();

    // 5. Add a line item to the purchase order
    await page.getByRole('button', { name: 'Add Item' }).click();
    await page.getByRole('button', { name: 'Select a product' }).click();
    // Select the first available product in the command list
    await page.locator('.cmdk-item').first().click();
    await page.fill('input[name="line_items.0.quantity"]', '10');

    // 6. Create the purchase order
    await page.getByRole('button', { name: 'Create Purchase Order' }).click();

    // 7. Verify the PO was created and we are on the edit page
    await page.waitForURL(/\/purchase-orders\/.*\/edit/, { timeout: 30000 });
    await expect(page.getByText(/Edit PO #/)).toBeVisible();
    
    // Check that the supplier name is correctly displayed on the edit page
    const supplierInput = page.locator('button[role="combobox"]');
    await expect(supplierInput).toContainText(newSupplierName);
  });
});

