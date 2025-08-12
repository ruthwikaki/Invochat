

import { test, expect } from '@playwright/test';
import credentials from '../test_data/test_credentials.json';
import type { Page } from '@playwright/test';


const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 60000 });
    await page.waitForLoadState('networkidle');
}

test.describe('E2E Business Workflow: Daily Operations', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
    await expect(page.getByTestId('dashboard-root').or(page.getByText('Welcome to ARVO'))).toBeVisible({ timeout: 60000 });
  });

  test('should allow a user to check the dashboard, ask AI, and check reorders', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForURL('/dashboard');
    await expect(page.getByTestId('dashboard-root').or(page.getByText('Welcome to ARVO'))).toBeVisible();

    await page.getByTestId('ask-ai-button').click();
    await page.waitForURL(/.*chat/);
    await expect(page.getByText('How can I help you today?')).toBeVisible();

    const input = page.locator('input[type="text"]');
    await input.fill('Show reorder suggestions');
    await page.locator('button[type="submit"]').click();

    await expect(page.getByTestId('reorder-list').or(page.getByText('No reorder suggestions'))).toBeVisible({ timeout: 15000 });

    await page.locator('a[href="/analytics/reordering"]').click();
    await page.waitForURL('/analytics/reordering');
    
    await expect(page.getByRole('heading', { name: 'Reorder Suggestions' })).toBeVisible();
    
    const firstRow = page.locator('table > tbody > tr').first();
    if (await firstRow.isVisible()) {
        const checkbox = firstRow.locator('input[type="checkbox"]');
        await checkbox.check();
        await expect(checkbox).toBeChecked();
        await checkbox.uncheck();
        await expect(checkbox).not.toBeChecked();
    } else {
        await expect(page.getByText('All Good! No Reorders Needed')).toBeVisible();
    }
  });
});
