

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    // Wait for either the empty state or the actual dashboard content
    await page.waitForSelector('text=/Welcome to ARVO|Sales Overview|Dashboard/', { timeout: 20000 });
}


test.describe('AI Chat Interface', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/chat');
        await page.waitForURL('/chat');
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
        const assistantMessageContainer = page.locator('.flex.flex-col.gap-3').last();
        await expect(assistantMessageContainer).toBeVisible({ timeout: 20000 });

        // Check for a non-error response. The exact text will vary.
        await expect(assistantMessageContainer).not.toContainText('An unexpected error occurred');
    });

    test('should trigger dead stock tool and render the correct UI component', async ({ page }) => {
        const hasQuickActions = await page.getByRole('button', { name: 'Show me my dead stock report' }).isVisible().catch(() => false);
  
        if (!hasQuickActions) {
            // Type the message instead
            await page.locator('input[placeholder*="Ask anything"]').fill('Show me my dead stock report');
            await page.getByRole('button', { name: 'Send message' }).click();
        } else {
            await page.getByRole('button', { name: 'Show me my dead stock report' }).click();
        }

        // Check that the user message appears
        await expect(page.getByText('Show me my dead stock report')).toBeVisible();
        
        await expect(page.getByTestId('dead-stock-table')).toBeVisible({ timeout: 20000 });
    });
    
    test('should trigger reorder tool and render the correct UI component', async ({ page }) => {
        // Use a more specific quick action button selector
        const hasQuickActions = await page.getByRole('button', { name: 'What should I order today?' }).isVisible().catch(() => false);

        if (!hasQuickActions) {
            await page.locator('input[placeholder*="Ask anything"]').fill('What should I order today?');
            await page.getByRole('button', { name: 'Send message' }).click();
        } else {
            await page.getByRole('button', { name: 'What should I order today?' }).click();
        }

        // Check that the user message appears
        await expect(page.getByText('What should I order today?')).toBeVisible();

        await expect(page.getByTestId('reorder-list')).toBeVisible({ timeout: 20000 });
    });

    test('should handle AI service error gracefully', async ({ page, context }) => {
        // Intercept the AI response and return an error
        await page.route('**/api/chat/message', async route => {
            const originalRequest = route.request();
            const response = await context.request.fetch(originalRequest);
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
