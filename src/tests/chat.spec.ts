import { test, expect } from '@playwright/test';

test.describe('AI Chat Interface', () => {
    test.beforeEach(async ({ page }) => {
        // For chat tests, we might need a logged-in state.
        // This would typically be handled by a global setup file that logs in once.
        // For now, let's assume we can visit the page directly if the test environment allows.
        await page.goto('/chat');
    });

    test('should send a message and receive a response', async ({ page }) => {
        // Check for the welcome message first
        await expect(page.getByText('How can I help you today?')).toBeVisible();

        const input = page.locator('input[type="text"]');
        await input.fill('What is my most profitable item?');
        await page.locator('button[type="submit"]').click();

        // Wait for the user's message to appear
        await expect(page.getByText('What is my most profitable item?')).toBeVisible();

        // Wait for the AI's response to appear (could be a loading indicator first)
        const assistantMessage = page.locator('.bg-card >> nth=0'); // First non-user message
        await expect(assistantMessage).toBeVisible();

        // Check for a non-error response. The exact text will vary.
        await expect(assistantMessage).not.toContainText('An unexpected error occurred');
    });

    test('should use a quick action button', async ({ page }) => {
        await page.getByRole('button', { name: 'Show me my dead stock report' }).click();

        // Check that the user message appears
        await expect(page.getByText('Show me my dead stock report')).toBeVisible();

        // Wait for the assistant's response. It will likely include a component.
        const deadStockTable = page.locator('h3:has-text("Dead Stock Report")');
        await expect(deadStockTable).toBeVisible({ timeout: 15000 }); // AI can be slow
    });

    test('should handle AI service error gracefully', async ({ page, context }) => {
        // Intercept the AI response and return an error
        await context.route('/api/chat', async route => {
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
