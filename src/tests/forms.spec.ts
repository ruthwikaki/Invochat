
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';
import path from 'path';

const testUser = credentials.test_users[0];

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Forms and Data Validation', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('should show validation errors on the supplier form', async ({ page }) => {
    await page.goto('/suppliers/new');
    await page.waitForURL('/suppliers/new');

    const submitButton = page.getByRole('button', { name: 'Create Supplier' });

    // 1. Attempt to submit an empty form
    await submitButton.click();
    
    // 2. Check for the name validation error
    await expect(page.getByText('Supplier name must be at least 2 characters.')).toBeVisible();

    // 3. Fill in the name, but provide an invalid email
    await page.locator('#name').fill('Test Supplier');
    await page.locator('#email').fill('not-an-email');
    await submitButton.click();

    // 4. Check for the email validation error
    await expect(page.getByText('Invalid email address.')).toBeVisible();
  });

  test('should handle file import validation', async ({ page }) => {
    await page.goto('/import');
    await page.waitForURL('/import');

    const importButton = page.getByRole('button', { name: 'Start Import' });
    
    // 1. Attempt to import without a file
    await expect(importButton).toBeDisabled();

    // 2. Upload a file
    const filePath = path.join(__dirname, 'test_data', 'sample-costs.csv');
    await page.locator('input[type="file"]').setInputFiles(filePath);

    // 3. Button should now be enabled
    await expect(importButton).toBeEnabled();

    // 4. Run a dry run and check for results
    await page.getByRole('checkbox', { name: 'Dry Run Mode' }).check();
    await importButton.click();
    
    // 5. Verify that the results card appears
    const resultsCard = page.locator('div:has-text("Dry Run Successful")');
    await expect(resultsCard).toBeVisible({ timeout: 10000 });
    await expect(resultsCard).toContainText('This file is valid');
  });

});
