
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Reordering Page', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/analytics/reordering');
  });

  test('should display AI reorder suggestions and allow selection', async ({ page }) => {
    // Check if the main heading is visible
    await expect(page.getByRole('heading', { name: 'Reorder Suggestions' })).toBeVisible();

    // The page can either have suggestions or an empty state. We need to handle both.
    const suggestionsTable = page.getByRole('table');
    const noSuggestionsMessage = page.getByText('No Reorder Suggestions');

    if (await suggestionsTable.isVisible()) {
      // If there are suggestions, test the selection interaction
      const firstCheckbox = suggestionsTable.locator('tbody > tr').first().getByRole('checkbox');
      await expect(firstCheckbox).toBeVisible();

      // The action bar should not be visible initially
      const actionBar = page.getByText(/item\(s\) selected/);
      await expect(actionBar).not.toBeVisible();

      // Click the checkbox to select the first item
      await firstCheckbox.click();

      // Now the action bar should appear
      await expect(actionBar).toBeVisible();
      await expect(page.getByRole('button', { name: 'Create PO(s)' })).toBeVisible();
      await expect(page.getByRole('button', { name: 'Export to CSV' })).toBeVisible();

    } else {
      // If there are no suggestions, verify the empty state message
      await expect(noSuggestionsMessage).toBeVisible();
      console.log('Test Execution Note: Reordering page is in empty state, skipping selection tests.');
    }
  });

});
