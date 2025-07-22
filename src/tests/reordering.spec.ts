import { test, expect } from '@playwright/test';

test.describe('Reordering Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/analytics/reordering');
    });

    test('should load reorder suggestions and allow selection', async ({ page }) => {
        await expect(page.getByText('AI-Enhanced Reorder Suggestions')).toBeVisible();

        // Check if there are any suggestions to test with
        const noSuggestions = page.getByText('No Reorder Suggestions');
        if (await noSuggestions.isVisible()) {
            console.log('No reorder suggestions to test, skipping selection test.');
            return;
        }

        const firstCheckbox = page.locator('table > tbody > tr').first().locator('input[type="checkbox"]');
        await expect(firstCheckbox).toBeChecked();

        const createPoButton = page.getByRole('button', { name: /Create PO/ });
        await expect(createPoButton).toBeVisible();

        // Uncheck the first item
        await firstCheckbox.uncheck();
        
        // Uncheck all
        await page.locator('table > thead').locator('input[type="checkbox"]').uncheck();
        
        // The "Create PO" button should disappear
        await expect(createPoButton).not.toBeVisible();
    });
});
