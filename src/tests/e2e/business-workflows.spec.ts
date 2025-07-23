import { test, expect } from '@playwright/test';

// This E2E test simulates a full "Day in the Life" workflow for a user.
// It combines multiple features to ensure they work together seamlessly.

test.describe('E2E Business Workflow: Daily Operations', () => {

  test.beforeEach(async ({ page }) => {
    // Start by logging in
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
  });

  test('should allow a user to check the dashboard, ask AI, and check reorders', async ({ page }) => {
    // 1. Check Dashboard
    await page.goto('/dashboard');
    await expect(page.getByText('Sales Overview')).toBeVisible();

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
    await expect(page.getByText('AI-Enhanced Reorder Suggestions')).toBeVisible();
    
    // Check if there are suggestions, if so, interact with the first one
    const firstRow = page.locator('table > tbody > tr').first();
    if (await firstRow.isVisible()) {
        const checkbox = firstRow.locator('input[type="checkbox"]');
        await expect(checkbox).toBeChecked();
        await checkbox.uncheck();
        await expect(checkbox).not.toBeChecked();
    } else {
        await expect(page.getByText('No Reorder Suggestions')).toBeVisible();
    }
  });
});
