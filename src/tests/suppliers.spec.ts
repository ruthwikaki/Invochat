
import { test, expect } from '@playwright/test';

test.describe('Supplier Management', () => {
  const newSupplierName = `Test Supplier ${Date.now()}`;
  const newSupplierEmail = `test-${Date.now()}@example.com`;

  test.beforeEach(async ({ page }) => {
    // Tests will use shared authentication state
    await page.goto('/suppliers');
    await page.waitForURL('/suppliers');
  });

  test('should create, update, and delete a supplier', async ({ page }) => {
    // 1. Create a new supplier
    await page.getByRole('link', { name: 'Add Supplier' }).click();
    await page.waitForURL('/suppliers/new');
    await expect(page.getByText('Add New Supplier')).toBeVisible();

    await page.fill('input[name="name"]', newSupplierName);
    await page.fill('input[name="email"]', newSupplierEmail);
    await page.fill('input[name="default_lead_time_days"]', '14');
    
    // Submit and wait for either success redirect or stay on form with error
    await page.click('button[type="submit"]');
    
    // Wait a bit for form processing
    await page.waitForTimeout(2000);
    
    // Check if we're back on suppliers page (success) or still on form (error)
    const currentUrl = page.url();
    if (currentUrl.includes('/suppliers/new')) {
      // Still on form, check for errors
      const errorElement = page.locator('.text-destructive, .text-red-500, [role="alert"]').first();
      if (await errorElement.isVisible()) {
        const errorText = await errorElement.textContent();
        throw new Error(`Form submission failed: ${errorText}`);
      } else {
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
    await page.click('button[type="submit"]');

    // 4. Verify the update
    await page.waitForURL('/suppliers');
    await expect(page.getByText(updatedName)).toBeVisible();
    await expect(page.getByText(newSupplierName)).not.toBeVisible();

    // 5. Delete the supplier
    const updatedRow = page.locator('tr', { hasText: updatedName });
    await updatedRow.getByRole('button').click();
    await page.click('div[role="menuitem"]:has-text("Delete")');

    await expect(page.getByText('Are you sure?')).toBeVisible();
    await page.click('button:has-text("Yes, delete")');

    // 6. Verify the deletion
    await expect(page.getByText(updatedName)).not.toBeVisible();
    await expect(page.getByText('Supplier Deleted').first()).toBeVisible();
  });
});

    