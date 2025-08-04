
import { test, expect } from '@playwright/test';

test.describe('Reordering Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/login');
        await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
        await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
        await page.click('button[type="submit"]');
        await page.waitForURL('/dashboard');
        await page.goto('/analytics/reordering');
    });

    test('should load reorder suggestions and allow selection', async ({ page }) => {
        await expect(page.getByText('Reorder Suggestions')).toBeVisible();

        // Check if there are any suggestions to test with or if the empty state is shown
        const noSuggestions = page.getByText('All Good! No Reorders Needed');
        const firstRow = page.locator('table > tbody > tr').first();
        
        await expect(firstRow.or(noSuggestions)).toBeVisible();

        if (await firstRow.isVisible()) {
            const firstCheckbox = firstRow.locator('input[type="checkbox"]');
            const createPoButton = page.getByRole('button', { name: /Create PO/ });

            await expect(createPoButton).not.toBeVisible();
            
            await firstCheckbox.check();
            await expect(firstCheckbox).toBeChecked();
            
            await expect(createPoButton).toBeVisible();

            // Uncheck the first item
            await firstCheckbox.uncheck();
            await expect(createPoButton).not.toBeVisible();
            
            // Uncheck all via header
            const headerCheckbox = page.locator('table > thead').locator('input[type="checkbox"]');
            await headerCheckbox.check();
            await expect(createPoButton).toBeVisible();
            await headerCheckbox.uncheck();
            await expect(createPoButton).not.toBeVisible();
        } else {
            console.log('No reorder suggestions to test, verifying empty state.');
            await expect(noSuggestions).toBeVisible();
        }
    });

    test('should show AI reasoning in a tooltip', async ({ page }) => {
        const aiReasoningCell = page.getByText('AI Adjusted').first();
        
        if (await aiReasoningCell.isVisible()) {
            await aiReasoningCell.hover();
            // The tooltip is rendered in a portal, so we find it at the body level
            const tooltip = page.locator('[role="tooltip"]');
            await expect(tooltip).toBeVisible();
            await expect(tooltip).toContainText('AI Analysis');
            await expect(tooltip).toContainText('Confidence');
        } else {
            console.log('Skipping AI reasoning test, no adjusted items found.');
        }
    });
});
