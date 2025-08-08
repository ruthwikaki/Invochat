

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await expect(page.getByText('Sales Overview')).toBeVisible({ timeout: 60000 });
}

test.describe('Integrations Page', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
        await page.goto('/settings/integrations');
        await page.waitForURL('/settings/integrations');
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

