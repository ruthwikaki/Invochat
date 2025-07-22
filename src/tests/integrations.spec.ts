import { test, expect } from '@playwright/test';

test.describe('Integrations Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/settings/integrations');
    });

    test('should load available and connected integrations', async ({ page }) => {
        await expect(page.getByText('Connected Integrations')).toBeVisible();
        await expect(page.getByText('Available Integrations')).toBeVisible();
    });

    test('should open and close the Shopify connect modal', async ({ page }) => {
        // This assumes Shopify is an available integration
        const connectButton = page.getByRole('button', { name: 'Connect Store' }).first();
        await expect(connectButton).toBeVisible();
        await connectButton.click();
        
        await expect(page.getByText('Connect Your Shopify Store')).toBeVisible();
        await expect(page.getByLabel('Shopify Store URL')).toBeVisible();
        
        await page.getByRole('button', { name: 'Cancel' }).click();
        await expect(page.getByText('Connect Your Shopify Store')).not.toBeVisible();
    });

    test('should show validation errors in Shopify modal', async ({ page }) => {
        await page.getByRole('button', { name: 'Connect Store' }).first().click();
        
        const submitButton = page.getByRole('button', { name: 'Test & Connect' });
        await submitButton.click();
        
        await expect(page.getByText('Must be a valid URL')).toBeVisible();
        await expect(page.getByText('Token must start with "shpat_"')).toBeVisible();
    });

});
