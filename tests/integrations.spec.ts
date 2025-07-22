
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Integrations Management', () => {
  test.beforeEach(async ({ page, context }) => {
    // Reuse the login utility and navigate to the integrations page
    await login(page, context);
    await page.goto('/settings/integrations');
  });

  test('should allow a user to connect a Shopify store', async ({ page }) => {
    // 1. Verify the page has loaded correctly
    await expect(page.getByRole('heading', { name: 'Integrations' })).toBeVisible();

    // 2. Mock the API call for connecting to Shopify to avoid making a real external request.
    // This makes the test faster, more reliable, and secure.
    await page.route('/api/shopify/connect', async (route) => {
      const mockResponse = {
        success: true,
        integration: {
          id: 'mock_integration_id_123',
          platform: 'shopify',
          shop_name: 'Mocked Shopify Store',
        },
      };
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify(mockResponse),
      });
    });

    // 3. Find and click the "Connect Store" button for Shopify
    const shopifyCard = page.locator('div').filter({ hasText: 'Sync your products, inventory levels' }).first();
    const connectButton = shopifyCard.getByRole('button', { name: 'Connect Store' });
    await connectButton.click();

    // 4. The connection modal should now be visible
    const modal = page.getByRole('dialog');
    await expect(modal).toBeVisible();
    await expect(modal.getByRole('heading', { name: 'Connect Your Shopify Store' })).toBeVisible();

    // 5. Fill out the form within the modal
    await modal.getByLabel('Shopify Store URL').fill('https://mock-test-store.myshopify.com');
    await modal.getByLabel('Admin API Access Token').fill('shpat_mock_secret_token_1234567890');

    // 6. Submit the form
    await modal.getByRole('button', { name: 'Test & Connect' }).click();

    // 7. Verify the success toast appears, confirming the UI handled the mocked response correctly.
    const successToast = page.getByText('Your Shopify store has been connected.');
    await expect(successToast).toBeVisible({ timeout: 10000 });
  });

  test('should allow syncing an already connected store', async ({ page }) => {
    // This test assumes an integration card is already rendered
    const integrationCard = page.locator('div').filter({ hasText: /Last synced/ }).first();
    await expect(integrationCard).toBeVisible();

    // Mock the sync API call
    await page.route('/api/shopify/sync', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ success: true, message: "Sync started" }),
      });
    });

    const syncButton = integrationCard.getByRole('button', { name: 'Sync Now' });
    await syncButton.click();

    // Check for the "Sync Started" toast
    await expect(page.getByText('Sync Started')).toBeVisible();

    // The button should enter a temporary loading state
    await expect(integrationCard.getByText(/Starting sync/)).toBeVisible();
  });
});
