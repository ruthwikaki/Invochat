
import { test, expect } from '@playwright/test';
import path from 'path';

test.describe('Forms and Data Validation', () => {
  // Using shared authentication state - no beforeEach needed

  test('should show validation errors on the supplier form', async ({ page }) => {
    await page.goto('/suppliers/new');
    await page.waitForURL('/suppliers/new');
    await page.waitForLoadState('networkidle');

    // Wait for form to be fully loaded
    await page.waitForSelector('form', { timeout: 10000 });

    // 1. Find form inputs using more flexible selectors
    const nameInput = page.locator('input[name="name"], input[placeholder*="name"], #supplier-name').first();
    const emailInput = page.locator('input[name="email"], input[type="email"], input[placeholder*="email"]').first();
    const submitButton = page.locator('button[type="submit"], button:has-text("Create"), button:has-text("Submit")').first();

    // Wait for inputs to be available
    await nameInput.waitFor({ timeout: 5000 });
    await emailInput.waitFor({ timeout: 5000 });

    // Clear any existing values and ensure fields are empty
    await nameInput.clear();
    await emailInput.clear();

    // 2. Fill in name but use invalid email format
    await nameInput.fill('A'); // Too short for validation
    await emailInput.fill('invalid-email');
    
    // Submit to trigger validation
    await submitButton.click();
    await page.waitForTimeout(2000);

    // 3. Check for validation messages - use more flexible selectors
    const hasValidationError = await page.evaluate(() => {
      // Check for HTML5 validation
      const inputs = document.querySelectorAll('input');
      for (const input of inputs) {
        if (!input.checkValidity()) return true;
      }
      
      // Check for custom validation messages
      const errorElements = document.querySelectorAll('[class*="error"], [role="alert"], .text-red-500, .text-destructive');
      return errorElements.length > 0;
    });
    
    expect(hasValidationError).toBeTruthy();
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
