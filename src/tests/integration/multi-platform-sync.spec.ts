
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// This test assumes that the test user has both Shopify and WooCommerce integrations connected.
// In a real-world CI/CD pipeline, this setup would be part of a database seeding script.

test.describe('Multi-Platform Synchronization', () => {
    
    test.beforeAll(async () => {
        // Seeding logic: ensure both integrations exist for the test user's company.
        // This is a simplified version. A real setup would be more robust.
        const supabase = getServiceRoleClient();
        const { data: user } = await supabase.from('users' as any).select('app_metadata').eq('email', process.env.TEST_USER_EMAIL).single();
        const companyId = user?.app_metadata?.company_id;

        if (companyId) {
            await supabase.from('integrations').upsert([
                { company_id: companyId, platform: 'shopify', shop_name: 'Test Shopify for Multi-Sync' },
                { company_id: companyId, platform: 'woocommerce', shop_name: 'Test Woo for Multi-Sync' },
            ], { onConflict: 'company_id, platform' });
        }
    });

    test('should display and allow syncing for multiple connected platforms', async ({ page }) => {
        await page.goto('/settings/integrations');

        const connectedSection = page.getByTestId('integrations-connected');
        
        // Verify both integration cards are visible
        const shopifyCard = connectedSection.locator('.card', { hasText: 'Test Shopify for Multi-Sync' });
        const wooCard = connectedSection.locator('.card', { hasText: 'Test Woo for Multi-Sync' });

        await expect(shopifyCard).toBeVisible();
        await expect(wooCard).toBeVisible();

        // Trigger sync for Shopify
        await shopifyCard.getByRole('button', { name: 'Sync Now' }).click();
        await expect(shopifyCard.getByText(/Syncing/)).toBeVisible();
        
        // Wait for the sync to complete (or fail, doesn't matter for this UI test)
        // A success or failure message should appear.
        await expect(shopifyCard.getByText(/Last synced|Sync failed/)).toBeVisible({ timeout: 20000 });
        
        // Trigger sync for WooCommerce
        await wooCard.getByRole('button', { name: 'Sync Now' }).click();
        await expect(wooCard.getByText(/Syncing/)).toBeVisible();
        await expect(wooCard.getByText(/Last synced|Sync failed/)).toBeVisible({ timeout: 20000 });
    });
});

    