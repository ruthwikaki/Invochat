import { test, expect } from '@playwright/test';

test.describe('Supplier Management', () => {
  const newSupplierName = `Test Supplier ${Date.now()}`;
  const newSupplierEmail = `test-${Date.now()}@example.com`;

  test.beforeEach(async ({ page }) => {
    await page.goto('/suppliers');
  });

  test('should create, update, and delete a supplier', async ({ page }) => {
    // 1. Create a new supplier
    await page.click('a[href="/suppliers/new"]');
    await expect(page.getByText('Add New Supplier')).toBeVisible();

    await page.fill('input[name="name"]', newSupplierName);
    await page.fill('input[name="email"]', newSupplierEmail);
    await page.fill('input[name="default_lead_time_days"]', '14');
    await page.click('button[type="submit"]');

    // 2. Verify the supplier was created and is in the list
    await expect(page.getByText(newSupplierName)).toBeVisible();
    await expect(page.getByText(newSupplierEmail)).toBeVisible();
    await expect(page.getByText('14 days')).toBeVisible();

    // 3. Update the supplier
    const supplierRow = page.locator('tr', { hasText: newSupplierName });
    await supplierRow.locator('button[aria-haspopup="menu"]').click();
    await page.click('div[role="menuitem"]:has-text("Edit")');
    
    await expect(page.getByText(`Edit ${newSupplierName}`)).toBeVisible();
    const updatedName = `${newSupplierName} - Updated`;
    await page.fill('input[name="name"]', updatedName);
    await page.click('button[type="submit"]');

    // 4. Verify the update
    await expect(page.getByText(updatedName)).toBeVisible();
    await expect(page.getByText(newSupplierName)).not.toBeVisible();

    // 5. Delete the supplier
    const updatedRow = page.locator('tr', { hasText: updatedName });
    await updatedRow.locator('button[aria-haspopup="menu"]').click();
    await page.click('div[role="menuitem"]:has-text("Delete")');

    await expect(page.getByText('Are you sure?')).toBeVisible();
    await page.click('button:has-text("Yes, delete")');

    // 6. Verify the deletion
    await expect(page.getByText(updatedName)).not.toBeVisible();
    await expect(page.getByText('Supplier Deleted')).toBeVisible(); // Toast message
  });
});
