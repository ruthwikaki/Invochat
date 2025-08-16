

import { test, expect } from '@playwright/test';
import credentials from './test_data/test_credentials.json';
import { login } from './test-utils';

const testUser = credentials.test_users[0]; // Use the first user for tests

test.describe('Reordering Page', () => {
    test.beforeEach(async ({ page }) => {
        await login(page, testUser);
        await page.goto('/analytics/reordering');
        await page.waitForURL('/analytics/reordering');
    });

    test('should load reorder suggestions and allow selection', async ({ page }) => {
        await expect(page.getByRole('heading', { name: /Reorder Suggestions/i })).toBeVisible({ timeout: 10000 });

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

            await firstCheckbox.uncheck();
            await expect(createPoButton).not.toBeVisible();
            
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

    test('should show AI reasoning and validate quantity adjustment', async ({ page }) => {
        const firstRow = page.locator('table > tbody > tr').first();
        if (!await firstRow.isVisible({ timeout: 5000 })) {
            console.log('Skipping AI reasoning test, no reorder suggestions found.');
            return;
        }

        const aiReasoningCell = page.locator('td:has-text("AI Adjusted")').first();
        
        if (await aiReasoningCell.isVisible()) {
            await aiReasoningCell.hover();
            const tooltip = page.locator('[role="tooltip"]');
            await expect(tooltip).toBeVisible();
            await expect(tooltip).toContainText('AI Analysis');
            await expect(tooltip).toContainText('Confidence');

            const parentRow = aiReasoningCell.locator('xpath=./..');
            const baseQtyElement = parentRow.locator('td').nth(4); 
            const adjustedQtyElement = parentRow.locator('td').nth(5); 

            const baseQty = Number(await baseQtyElement.textContent());
            const adjustedQty = Number(await adjustedQtyElement.textContent());

            console.log(`Validating AI adjustment: Base Qty=${baseQty}, Adjusted Qty=${adjustedQty}`);
            
            expect(adjustedQty).not.toEqual(baseQty);
            
        } else {
            console.log('Skipping AI reasoning validation, no AI-adjusted items found on the first page.');
        }
    });
});
