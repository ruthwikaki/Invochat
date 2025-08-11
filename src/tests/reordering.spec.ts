

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 60000 });
}

test.describe('Reordering Page', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/analytics/reordering');
        await page.waitForURL('/analytics/reordering');
    });

    test('should load reorder suggestions and allow selection', async ({ page }) => {
        await expect(page.getByRole('heading', { name: /Reorder Suggestions/i })).toBeVisible({ timeout: 10000 });

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

    test('should show AI reasoning and validate quantity adjustment', async ({ page }) => {
        // Wait for the table to load
        const firstRow = page.locator('table > tbody > tr').first();
        if (!await firstRow.isVisible({ timeout: 5000 })) {
            console.log('Skipping AI reasoning test, no reorder suggestions found.');
            return;
        }

        const aiReasoningCell = page.locator('td:has-text("AI Adjusted")').first();
        
        if (await aiReasoningCell.isVisible()) {
            // 1. Validate the tooltip appears
            await aiReasoningCell.hover();
            const tooltip = page.locator('[role="tooltip"]');
            await expect(tooltip).toBeVisible();
            await expect(tooltip).toContainText('AI Analysis');
            await expect(tooltip).toContainText('Confidence');

            // 2. Validate the business logic: AI-adjusted quantity should differ from the base quantity
            const parentRow = aiReasoningCell.locator('xpath=./..');
            const baseQtyElement = parentRow.locator('td').nth(4); // 5th column
            const adjustedQtyElement = parentRow.locator('td').nth(5); // 6th column

            const baseQty = Number(await baseQtyElement.textContent());
            const adjustedQty = Number(await adjustedQtyElement.textContent());

            console.log(`Validating AI adjustment: Base Qty=${baseQty}, Adjusted Qty=${adjustedQty}`);
            
            // Assert that the AI has actually made an adjustment
            expect(adjustedQty).not.toEqual(baseQty);
            
        } else {
            console.log('Skipping AI reasoning validation, no AI-adjusted items found on the first page.');
        }
    });
});

    