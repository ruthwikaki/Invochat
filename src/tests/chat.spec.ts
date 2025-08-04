

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'owner_stylehub@test.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'StyleHub2024!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 15000 });
}


test.describe('AI Chat Interface', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/chat');
    });

    test('should send a message and receive a text response', async ({ page }) => {
        // Check for the welcome message first
        await expect(page.getByText('How can I help you today?')).toBeVisible();

        const input = page.locator('input[type="text"]');
        await input.fill('What is my most profitable item?');
        await page.locator('button[type="submit"]').click();

        // Wait for the user's message to appear
        await expect(page.getByText('What is my most profitable item?')).toBeVisible();

        // Wait for the AI's response to appear (could be a loading indicator first)
        const assistantMessageContainer = page.locator('div[role="log"] > div').last();
        await expect(assistantMessageContainer).toBeVisible({ timeout: 20000 });

        // Check for a non-error response. The exact text will vary.
        await expect(assistantMessageContainer).not.toContainText('An unexpected error occurred');
    });

    test('should trigger a tool and render the correct UI component', async ({ page }) => {
        await page.getByRole('button', { name: 'Show me my dead stock report' }).click();

        // Check that the user message appears
        await expect(page.getByText('Show me my dead stock report')).toBeVisible();

        // Wait for the assistant's response. It should render the DeadStockTable component,
        // which has a specific card title. This is a much stronger assertion than checking for text.
        const assistantMessageContainer = page.locator('div[role="log"] > div').last();
        const deadStockTableTitle = assistantMessageContainer.locator('h3:has-text("Dead Stock Report")');
        
        await expect(deadStockTableTitle).toBeVisible({ timeout: 20000 });
    });

    test('should handle AI service error gracefully', async ({ page, context }) => {
        // Intercept the AI response and return an error
        await context.route('**/api/chat/message', async route => {
            await route.fulfill({
                status: 500,
                contentType: 'application/json',
                body: JSON.stringify({ error: 'AI service is currently unavailable.' }),
            });
        });

        const input = page.locator('input[type="text"]');
        await input.fill('This will fail');
        await page.locator('button[type="submit"]').click();

        // Check for a user-facing error message in the chat
        await expect(page.getByText('AI service is currently unavailable.')).toBeVisible();
    });
});
