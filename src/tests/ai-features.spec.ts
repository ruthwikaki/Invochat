
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0];

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('AI-Specific Feature Tests', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('should generate results on the AI Insights page', async ({ page }) => {
    await page.goto('/analytics/ai-insights');
    await page.waitForURL('/analytics/ai-insights');

    // Test the Hidden Money Finder
    const hiddenMoneyButton = page.getByRole('button', { name: 'Find Opportunities' });
    await expect(hiddenMoneyButton).toBeVisible();
    await hiddenMoneyButton.click();

    // Wait for the response and check for either results or a no-data message
    const hiddenMoneyResults = page.locator('h4:has-text("AI Business Consultant\'s Summary") + div').or(page.getByText('did not find any specific hidden money opportunities'));
    await expect(hiddenMoneyResults).toBeVisible({ timeout: 20000 });

    // Test the Price Optimizer
    const priceOptimizerButton = page.getByRole('button', { name: 'Generate Price Suggestions' });
    await expect(priceOptimizerButton).toBeVisible();
    await priceOptimizerButton.click();

    const priceOptimizationResults = page.locator('h4:has-text("AI Pricing Analyst\'s Summary") + div').or(page.getByText('could not generate price suggestions'));
    await expect(priceOptimizationResults).toBeVisible({ timeout: 20000 });
  });

  test('should allow submitting feedback on a chat message', async ({ page }) => {
    await page.goto('/chat');
    await page.waitForURL('/chat');

    const input = page.locator('input[type="text"]');
    await input.fill('What is my most profitable item?');
    await page.getByRole('button', { name: 'Send message' }).click();

    // Wait for the assistant's response to appear
    const assistantMessageContainer = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
    await expect(assistantMessageContainer).toBeVisible({ timeout: 20000 });
    
    // Find the feedback buttons
    const thumbsUpButton = assistantMessageContainer.getByRole('button', { name: 'Thumbs Up' });
    await expect(thumbsUpButton).toBeVisible();

    // Click the feedback button
    await thumbsUpButton.click();

    // Verify the feedback confirmation message appears
    await expect(assistantMessageContainer.getByText('Thank you for your feedback!')).toBeVisible();
    await expect(thumbsUpButton).not.toBeVisible();
  });

});
