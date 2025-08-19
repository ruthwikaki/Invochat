
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// Helper to get a variant's stock from the database directly
async function getStockForSku(sku: string): Promise<number | null> {
    const supabase = getServiceRoleClient();
    const { data } = await supabase.from('product_variants').select('inventory_quantity').eq('sku', sku).single();
    return data?.inventory_quantity ?? null;
}

test.describe('Complex Inventory Workflows', () => {
    // Using shared authentication state - no login needed

    test('should correctly update stock after receiving a purchase order', async ({ page }) => {
        await page.goto('/inventory');
        
        const firstRow = page.locator('table > tbody > tr').first();
        await expect(firstRow).toBeVisible({ timeout: 10000 });
        
        // Look for expand button with more flexible selectors
        const expandButton = firstRow.locator('button').filter({ hasText: /expand|chevron|down|arrow/i }).or(
            firstRow.locator('button[aria-label*="expand"]')
        ).or(
            firstRow.locator('button svg')
        ).first();
        
        await expect(expandButton).toBeVisible({ timeout: 5000 });
        await expandButton.click();
        const variantRow = page.locator('table table tbody tr').first();
        const sku = await variantRow.locator('td').nth(1).innerText();
        const initialStock = parseInt(await variantRow.locator('td').nth(4).innerText(), 10);
        
        const orderQuantity = 10;
        
        // Create a PO for this item
        await page.goto('/purchase-orders/new');
        await page.locator('button[role="combobox"]').first().click();
        await page.locator('.cmdk-item').first().click(); // Select first supplier
        await page.locator('button:has-text("Add Item")').click();
        await page.locator('button[role="combobox"]').last().click();
        await page.locator(`[cmdk-item][value*="${sku}"]`).click();
        await page.locator('input[name="line_items.0.quantity"]').fill(String(orderQuantity));
        await page.locator('button:has-text("Create Purchase Order")').click();
        
        // Wait for redirect to edit page and change status
        await page.waitForURL(/\/purchase-orders\/.*\/edit/);
        await page.locator('button[role="combobox"]').last().click();
        await page.locator('[cmdk-item-value="Received"]').click();
        await page.locator('button:has-text("Save Changes")').click();

        await page.waitForURL('/purchase-orders');
        
        // Verify stock has been updated
        const newStock = await getStockForSku(sku);
        expect(newStock).toBe(initialStock + orderQuantity);
    });

    test('should manually adjust inventory and verify history', async ({ page }) => {
        await page.goto('/inventory');
        const firstRow = page.locator('table > tbody > tr').first();
        await expect(firstRow).toBeVisible({ timeout: 10000 });

        // Look for expand button with more flexible selectors
        const expandButton = firstRow.locator('button').filter({ hasText: /expand|chevron|down|arrow/i }).or(
            firstRow.locator('button[aria-label*="expand"]')
        ).or(
            firstRow.locator('button svg')
        ).first();
        
        await expect(expandButton).toBeVisible({ timeout: 5000 });
        await expandButton.click();
        const variantRow = page.locator('table table tbody tr').first();
        const sku = await variantRow.locator('td').nth(1).innerText();
        const initialStock = parseInt(await variantRow.locator('td').nth(4).innerText(), 10);
        
        await variantRow.locator('button[aria-label="View history"]').click();
        
        const dialog = page.locator('[role="dialog"]');
        await expect(dialog).toBeVisible();
        await expect(dialog).toContainText(`Inventory History: ${sku}`);
        
        const newQuantity = initialStock + 5;
        await dialog.locator('input#newQuantity').fill(String(newQuantity));
        await dialog.locator('input#reason').fill('Test adjustment');
        await dialog.locator('button:has-text("Adjust Stock")').click();

        await expect(page.getByText('Inventory Updated')).toBeVisible();

        // Close the dialog and verify the table UI has updated
        await page.locator('button[aria-label="Close"]').click();
        await page.waitForTimeout(500); // Wait for potential UI update
        
        await expect(variantRow.locator('td').nth(4)).toContainText(String(newQuantity));
    });
});
