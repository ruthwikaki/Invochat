
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Page } from '@playwright/test';

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'owner_stylehub@test.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'StyleHub2024!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 15000 });
}

// Helper function to calculate expected dead stock value from the database
async function calculateExpectedDeadStockValue(sku: string): Promise<number> {
    const supabase = getServiceRoleClient();
    const { data: variant, error } = await supabase
        .from('product_variants')
        .select('cost, inventory_quantity')
        .eq('sku', sku)
        .single();
    
    if (error || !variant) {
        throw new Error(`Could not find variant with SKU: ${sku}. Error: ${error?.message}`);
    }

    const cost = variant.cost || 0;
    const quantity = variant.inventory_quantity || 0;
    
    return cost * quantity;
}


test.describe('Business Logic & Analytics Validation', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('dead stock calculations should be accurate', async ({ page }) => {
    await page.goto('/analytics/dead-stock');

    // Wait for the report to be visible
    await expect(page.getByText('Dead Stock Report')).toBeVisible({ timeout: 10000 });
    
    const firstRow = page.locator('table > tbody > tr').first();
    const isVisible = await firstRow.isVisible({ timeout: 5000 }).catch(() => false);

    if (!isVisible) {
      // If there's no dead stock, the test passes but we log a warning.
      console.warn('⚠️ No dead stock items found to validate. Test is trivially passing.');
      await expect(page.getByText('No Dead Stock Found!')).toBeVisible();
      return;
    }

    // Extract SKU and displayed value from the UI
    const skuElement = firstRow.locator('td').nth(0).locator('div.text-xs');
    const valueElement = firstRow.locator('td').nth(2);

    const sku = await skuElement.textContent();
    const displayedValueText = await valueElement.textContent();
    
    expect(sku).not.toBeNull();
    expect(displayedValueText).not.toBeNull();

    // Clean and parse the currency value from the UI
    const displayedValueCents = Math.round(parseFloat(displayedValueText!.replace(/[^0-9.-]+/g, '')) * 100);
    
    // Calculate the expected value using our helper against the database
    const expectedValueCents = await calculateExpectedDeadStockValue(sku!);
    
    // Validate that the UI shows the correct calculation
    expect(displayedValueCents).toBe(expectedValueCents);
  });

});
