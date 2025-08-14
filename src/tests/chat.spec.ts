

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}


test.describe('AI Chat Interface', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/chat');
        await page.waitForURL('/chat');
    });

    test('should send a message and receive a text response', async ({ page }) => {
        await expect(page.getByText('How can I help you today?')).toBeVisible();

        const responsePromise = page.waitForResponse(resp => resp.url().includes('/api/chat/message') && resp.status() === 200);

        await page.locator('input[placeholder*="Ask anything"]').fill('What is my most profitable item?');
        await page.getByRole('button', { name: 'Send message' }).click();

        await responsePromise;

        const assistantMessageContainer = page.locator('.flex.flex-col.gap-3').last();
        await expect(assistantMessageContainer).toBeVisible({ timeout: 20000 });
        await expect(assistantMessageContainer).not.toContainText('An unexpected error occurred');
    });

    test('should trigger dead stock tool and render the correct UI component', async ({ page }) => {
        const hasQuickActions = await page.getByRole('button', { name: 'Show me my dead stock report' }).isVisible({ timeout: 2000 }).catch(() => false);
  
        if (!hasQuickActions) {
            await page.locator('input[placeholder*="Ask anything"]').fill('Show me my dead stock report');
            await page.getByRole('button', { name: 'Send message' }).click();
        } else {
            await page.getByRole('button', { name: 'Show me my dead stock report' }).click();
        }

        await expect(page.getByText('Show me my dead stock report')).toBeVisible();
        
        await expect(page.getByTestId('dead-stock-table').or(page.getByText('No dead stock items found'))).toBeVisible({ timeout: 20000 });
    });
    
    test('should trigger reorder tool and render the correct UI component', async ({ page }) => {
        const hasQuickActions = await page.getByRole('button', { name: 'What should I order today?' }).isVisible({ timeout: 2000 }).catch(() => false);

        if (!hasQuickActions) {
            await page.locator('input[placeholder*="Ask anything"]').fill('What should I order today?');
            await page.getByRole('button', { name: 'Send message' }).click();
        } else {
            await page.getByRole('button', { name: 'What should I order today?' }).click();
        }

        await expect(page.getByText('What should I order today?')).toBeVisible();

        await expect(page.getByTestId('reorder-list').or(page.getByText('No reorder suggestions'))).toBeVisible({ timeout: 20000 });
    });

    test('should handle AI service error gracefully', async ({ page }) => {
        await page.route('**/api/chat/message', async route => {
            await route.fulfill({
                status: 500,
                contentType: 'application/json',
                body: JSON.stringify({ error: 'AI service is currently unavailable.' }),
            });
        });

        const input = page.locator('input[type="text"]');
        await input.fill('This will fail');
        await page.locator('button[type="submit"]').click();

        await expect(page.getByText('AI service is currently unavailable.')).toBeVisible();
    });
});
