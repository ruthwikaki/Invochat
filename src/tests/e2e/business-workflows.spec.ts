

import { test, expect } from '@playwright/test';
import credentials from '../test_data/test_credentials.json';
import type { Page } from '@playwright/test';


const testUser = credentials.test_users[0]; // Use the first user for tests

// This E2E test simulates a full "Day in the Life" workflow for a user.
// It combines multiple features to ensure they work together seamlessly.

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    // Wait for navigation to complete, not for specific content that might fail on its own.
    await page.waitForURL('/dashboard', { timeout: 60000 });
}

test.describe('E2E Business Workflow: Daily Operations', () => {

  test.beforeEach(async ({ page }) => {
    // Start by logging in
    await login(page);
    // After login, explicitly wait for a key element on the dashboard to ensure it's loaded.
    await expect(page.getByTestId('dashboard-root')).toBeVisible({ timeout: 60000 });
  });

  test('should allow a user to check the dashboard, ask AI, and check reorders', async ({ page }) => {
    // 1. Check Dashboard
    await page.goto('/dashboard');
    await page.waitForURL('/dashboard');
    await expect(page.getByTestId('dashboard-root')).toBeVisible();

    // 2. Ask the AI a question from the dashboard quick actions
    await page.getByRole('button', { name: 'Ask AI' }).click();
    await page.waitForURL(/.*chat/);
    await expect(page.getByText('How can I help you today?')).toBeVisible();

    const input = page.locator('input[type="text"]');
    await input.fill('Show reorder suggestions');
    await page.locator('button[type="submit"]').click();

    // Wait for the AI to respond, potentially with a reorder list component
    await expect(page.getByText('Reorder Suggestions')).toBeVisible({ timeout: 15000 });

    // 3. Navigate to the reordering page from the sidebar
    await page.locator('a[href="/analytics/reordering"]').click();
    await page.waitForURL('/analytics/reordering');
    
    // 4. Interact with the reordering page
    await expect(page.getByRole('heading', { name: 'Reorder Suggestions' })).toBeVisible();
    
    // Check if there are suggestions, if so, interact with the first one
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

    