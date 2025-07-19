
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Supplier Management', () => {

  const uniqueSupplierName = `Test Supplier ${Date.now()}`;
  const initialPhoneNumber = '123-456-7890';
  const updatedPhoneNumber = '987-654-3210';

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

  test('should allow creating, editing, and deleting a supplier', async ({ page }) => {
    // 1. CREATE: Navigate to the new supplier form
    await page.getByRole('link', { name: 'Add Supplier' }).click();
    await expect(page.getByRole('heading', { name: 'Add New Supplier' })).toBeVisible();

    // 2. Fill out and submit the form
    await page.getByLabel('Supplier Name').fill(uniqueSupplierName);
    await page.getByLabel('Contact Email').fill('test.supplier@example.com');
    await page.getByLabel('Phone Number').fill(initialPhoneNumber);
    await page.getByRole('button', { name: 'Create Supplier' }).click();

    // 3. READ: Verify redirection and that the new supplier is in the table
    await expect(page).toHaveURL('/suppliers');
    const supplierRow = page.getByRole('row', { name: new RegExp(uniqueSupplierName) });
    await expect(supplierRow).toBeVisible();
    await expect(supplierRow).toContainText('test.supplier@example.com');
    await expect(supplierRow).toContainText(initialPhoneNumber);

    // 4. UPDATE: Find the edit button and navigate to the edit page
    await supplierRow.getByRole('button').click(); // Clicks the 'MoreHorizontal' dropdown trigger
    await page.getByRole('menuitem', { name: 'Edit' }).click();
    await expect(page.getByRole('heading', { name: `Edit ${uniqueSupplierName}`})).toBeVisible();

    // 5. Change a value and save
    await page.getByLabel('Phone Number').fill(updatedPhoneNumber);
    await page.getByRole('button', { name: 'Save Changes' }).click();

    // 6. VERIFY UPDATE: Check the table for the updated phone number
    await expect(page).toHaveURL('/suppliers');
    await expect(supplierRow).toBeVisible();
    await expect(supplierRow).toContainText(updatedPhoneNumber);
    await expect(supplierRow).not.toContainText(initialPhoneNumber);

    // 7. DELETE: Clean up by deleting the supplier
    await supplierRow.getByRole('button').click();
    await page.getByRole('menuitem', { name: 'Delete' }).click();
    
    // 8. Confirm deletion in the dialog
    const dialog = page.getByRole('alertdialog');
    await expect(dialog.getByRole('heading', { name: 'Are you sure?' })).toBeVisible();
    await dialog.getByRole('button', { name: 'Yes, delete' }).click();

    // 9. Verify the supplier is no longer in the table
    await expect(page.getByText('Supplier Deleted')).toBeVisible(); // Check for the success toast
    await expect(supplierRow).not.toBeVisible();
  });

});
