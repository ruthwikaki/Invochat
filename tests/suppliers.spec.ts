
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Supplier Management', () => {

  const uniqueSupplierName = `Test Supplier ${Date.now()}`;

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/suppliers');
  });

  test('should show validation errors for an empty form', async ({ page }) => {
    // 1. Navigate to the new supplier form
    await page.getByRole('link', { name: 'Add Supplier' }).click();
    await expect(page.getByRole('heading', { name: 'Add New Supplier' })).toBeVisible();
    
    // 2. Click create without filling out the form
    await page.getByRole('button', { name: 'Create Supplier' }).click();

    // 3. Assert that we are still on the same page and error messages are visible
    await expect(page).toHaveURL('/suppliers/new');
    await expect(page.getByText('Supplier name must be at least 2 characters.')).toBeVisible();

    // 4. Test invalid email format
    await page.getByLabel('Supplier Name').fill('Valid Name');
    await page.getByLabel('Contact Email').fill('not-an-email');
    await page.getByRole('button', { name: 'Create Supplier' }).click();
    await expect(page.getByText('Please enter a valid email address.')).toBeVisible();
  });

  test('should allow creating and deleting a supplier', async ({ page }) => {
    // 1. Navigate to the new supplier form
    await page.getByRole('link', { name: 'Add Supplier' }).click();
    await expect(page.getByRole('heading', { name: 'Add New Supplier' })).toBeVisible();

    // 2. Fill out and submit the form
    await page.getByLabel('Supplier Name').fill(uniqueSupplierName);
    await page.getByLabel('Contact Email').fill('test.supplier@example.com');
    await page.getByLabel('Phone Number').fill('123-456-7890');
    await page.getByRole('button', { name: 'Create Supplier' }).click();

    // 3. Verify redirection and that the new supplier is in the table
    await expect(page).toHaveURL('/suppliers');
    const supplierRow = page.getByRole('row', { name: uniqueSupplierName });
    await expect(supplierRow).toBeVisible();
    await expect(supplierRow).toContainText('test.supplier@example.com');

    // 4. Delete the newly created supplier to clean up
    await supplierRow.getByRole('button').click(); // Clicks the 'MoreHorizontal' dropdown trigger
    await page.getByRole('menuitem', { name: 'Delete' }).click();
    
    // 5. Confirm deletion in the dialog
    const dialog = page.getByRole('alertdialog');
    await expect(dialog.getByRole('heading', { name: 'Are you sure?' })).toBeVisible();
    await dialog.getByRole('button', { name: 'Yes, delete' }).click();

    // 6. Verify the supplier is no longer in the table
    await expect(page.getByText('Supplier Deleted')).toBeVisible(); // Check for the success toast
    await expect(supplierRow).not.toBeVisible();
  });

});
