
import { test, expect } from '@playwright/test';
import path from 'path';

test.describe('Forms and Data Validation', () => {
  // Using shared authentication state - no beforeEach needed

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

    // Wait for the page to load completely
    await page.waitForSelector('.grid', { timeout: 10000 });
    
    // 1. Upload a file first (this will make the Start Import button appear)
    const filePath = path.join(__dirname, 'test_data', 'sample-costs.csv');
    await page.locator('input[type="file"]').setInputFiles(filePath);

    // 2. Wait for the Start Import button to appear after file upload
    const startImportButton = page.locator('button:has-text("Start Import")');
    await expect(startImportButton).toBeVisible({ timeout: 10000 });
    
    // 3. The button should be enabled since we have a file
    await expect(startImportButton).toBeEnabled({ timeout: 5000 });

    // 4. Check dry run checkbox if not already checked
    const dryRunCheckbox = page.getByRole('checkbox', { name: 'Dry Run Mode' });
    const isChecked = await dryRunCheckbox.isChecked().catch(() => false);
    if (!isChecked) {
      await dryRunCheckbox.check();
    }
    
    // 5. Click import and wait for processing
    await startImportButton.click();
    
    // 6. Verify that processing starts by looking for specific processing heading
    const processingHeading = page.getByRole('heading', { name: 'Processing...' });
    await expect(processingHeading).toBeVisible({ timeout: 20000 });
  });

});
