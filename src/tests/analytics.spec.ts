
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// Use shared authentication setup instead of custom login
test.use({ storageState: 'playwright/.auth/user.json' });

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
  test('dead stock calculations should be accurate', async ({ page }) => {
    await page.goto('/analytics/dead-stock');
    await page.waitForURL('/analytics/dead-stock');

    await expect(page.getByText('Dead Stock Report').or(page.getByText('No Dead Stock Found'))).toBeVisible({ timeout: 10000 });
    
    const firstRow = page.locator('table > tbody > tr').first();
    const isVisible = await firstRow.isVisible({ timeout: 5000 }).catch(() => false);

    if (!isVisible) {
      console.warn('⚠️ No dead stock items found to validate. Test is trivially passing.');
      await expect(page.getByText('No Dead Stock Found!')).toBeVisible();
      return;
    }

    const skuElement = firstRow.locator('td').nth(0).locator('div.text-xs');
    const valueElement = firstRow.locator('td').nth(2);

    const sku = await skuElement.textContent();
    const displayedValueText = await valueElement.textContent();
    
    expect(sku).not.toBeNull();
    expect(displayedValueText).not.toBeNull();

    const displayedValueCents = Math.round(parseFloat(displayedValueText!.replace(/[^0-9.-]+/g, '')) * 100);
    
    const expectedValueCents = await calculateExpectedDeadStockValue(sku!);
    
    expect(displayedValueCents).toBe(expectedValueCents);
  });

});
