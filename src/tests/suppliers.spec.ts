
import { test, expect } from '@playwright/test';

test.describe('Supplier Management', () => {
  const newSupplierName = `Test Supplier ${Date.now()}`;
  const newSupplierEmail = `test-${Date.now()}@example.com`;

  test.beforeEach(async ({ page }) => {
    // Navigate directly to suppliers page - authentication should already be handled by chromium project
    await page.goto('/suppliers');
    await page.waitForURL('/suppliers');
  });

  test('should create, update, and delete a supplier', async ({ page }) => {
    // 1. Create a new supplier
    await page.getByRole('link', { name: 'Add Supplier' }).click();
    await page.waitForURL('/suppliers/new');
    await expect(page.getByText('Add New Supplier')).toBeVisible();
    
    // Give extra time for the form and CSRF token to initialize
    await page.waitForTimeout(3000);

    await page.fill('input[name="name"]', newSupplierName);
    await page.fill('input[name="email"]', newSupplierEmail);
    await page.fill('input[name="default_lead_time_days"]', '14');
    
    // Wait for the CSRF token to load and submit button to be enabled (longer timeout)
    await page.waitForSelector('button[type="submit"]:not([disabled])', { timeout: 30000 });
    
    // Submit and wait for either success redirect or stay on form with error
    await page.click('button[type="submit"]');
    
    // Wait a bit for form processing
    await page.waitForTimeout(2000);
    
    // Check if we're back on suppliers page (success) or still on form (error)
    const currentUrl = page.url();
    console.log('Current URL after form submission:', currentUrl);
    
    if (currentUrl.includes('/suppliers/new')) {
      // Still on form, check for errors
      console.log('Still on form page, checking for errors...');
      const errorElement = page.locator('.text-destructive, .text-red-500, [role="alert"]').first();
      if (await errorElement.isVisible()) {
        const errorText = await errorElement.textContent();
        console.log('Error found:', errorText);
        throw new Error(`Form submission failed: ${errorText}`);
      } else {
        console.log('No error element visible, dumping page content...');
        const bodyText = await page.textContent('body');
        console.log('Page content (first 1000 chars):', bodyText?.substring(0, 1000));
        throw new Error('Form submission did not redirect and no error shown');
      }
    }

    // 2. Verify the supplier was created and is in the list
    await page.waitForURL('/suppliers', { timeout: 10000 });
    const newRow = page.locator('tr', { hasText: newSupplierName });
    await expect(newRow).toBeVisible();
    await expect(newRow).toContainText(newSupplierEmail);
    await expect(newRow.locator('td', { hasText: '14 days' })).toBeVisible();


    // 3. Update the supplier
    const supplierRow = page.locator('tr', { hasText: newSupplierName });
    await supplierRow.getByRole('button').click();
    await page.click('div[role="menuitem"]:has-text("Edit")');
    await page.waitForTimeout(1000); // Wait for modal
    
    const updatedName = `Updated Corp ${Date.now()}`;
    await page.fill('input[name="name"]', updatedName);
    
    // Wait for the CSRF token to load and submit button to be enabled (longer timeout)
    await page.waitForSelector('button[type="submit"]:not([disabled])', { timeout: 30000 });
    
    await page.click('button[type="submit"]');

    // 4. Verify the update
    await page.waitForURL('/suppliers');
    await expect(page.getByText(updatedName)).toBeVisible();
    await expect(page.getByText(newSupplierName)).not.toBeVisible();

    // 5. Delete the supplier
    const updatedRow = page.locator('tr', { hasText: updatedName });
    
    // Wait for any toasts to disappear first
    await page.waitForTimeout(2000);
    
    // Try clicking the menu button, with retry logic for toast interference
    let attempts = 0;
    while (attempts < 3) {
      try {
        await updatedRow.getByRole('button').click({ timeout: 5000 });
        break;
      } catch (error) {
        attempts++;
        if (attempts >= 3) throw error;
        await page.waitForTimeout(1000);
        // Dismiss any toasts that might be in the way
        await page.keyboard.press('Escape');
      }
    }
    
    await page.click('div[role="menuitem"]:has-text("Delete")');

    await expect(page.getByText('Are you sure?')).toBeVisible();
    await page.click('button:has-text("Yes, delete")');

    // 6. Verify the deletion
    await expect(page.getByText(updatedName)).not.toBeVisible();
    await expect(page.getByText('Supplier Deleted').first()).toBeVisible();
  });
});

    