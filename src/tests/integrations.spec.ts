import { test, expect } from '@playwright/test';

test.describe('Integrations Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/login');
        await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
        await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
        await page.click('button[type="submit"]');
        await page.waitForURL('/dashboard');
        await page.goto('/settings/integrations');
    });

    test('should load available and connected integrations', async ({ page }) => {
        await expect(page.getByText('Connected Integrations')).toBeVisible();
        await expect(page.getByText('Available Integrations')).toBeVisible();
    });

    test('should open and close the Shopify connect modal', async ({ page }) => {
        const shopifyCard = page.locator('.card', { hasText: 'Shopify' });
        // This test assumes Shopify is not yet connected
        const connectButton = shopifyCard.getByRole('button', { name: 'Connect Store' });
        
        if (!await connectButton.isVisible()) {
            console.log('Shopify is already connected, skipping modal open test.');
            return;
        }
        
        await connectButton.click();
        
        await expect(page.getByText('Connect Your Shopify Store')).toBeVisible();
        await expect(page.getByLabel('Shopify Store URL')).toBeVisible();
        
        await page.getByRole('button', { name: 'Cancel' }).click();
        await expect(page.getByText('Connect Your Shopify Store')).not.toBeVisible();
    });

    test('should show validation errors in Shopify modal', async ({ page }) => {
        const shopifyCard = page.locator('.card', { hasText: 'Shopify' });
        const connectButton = shopifyCard.getByRole('button', { name: 'Connect Store' });
        if (!await connectButton.isVisible()) return; // Skip if connected
        await connectButton.click();
        
        const submitButton = page.getByRole('button', { name: 'Test & Connect' });
        await submitButton.click();
        
        await expect(page.getByText('Must be a valid URL')).toBeVisible();
        await expect(page.getByText('Token must start with "shpat_"')).toBeVisible();
    });

});
