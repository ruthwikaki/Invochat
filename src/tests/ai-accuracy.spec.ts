
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { DashboardMetrics } from '@/types';

// Use shared authentication setup instead of custom login
test.use({ storageState: 'playwright/.auth/user.json' });

// Helper to get ground truth directly from the database
async function getGroundTruth(): Promise<{ topProduct: string | null }> {
    const supabase = getServiceRoleClient();
    
    // Use the company ID from shared auth setup (TechGear Electronics)
    const { data: company } = await supabase
        .from('companies')
        .select('id')
        .eq('name', 'TechGear Electronics')
        .single();

    if (!company) {
        throw new Error(`Test company "TechGear Electronics" not found.`);
    }

    // Call the same RPC function the dashboard uses to get top products
    const { data, error } = await supabase.rpc('get_dashboard_metrics', {
        p_company_id: company.id,
        p_days: 90
    });

    if (error) {
        throw new Error(`Database RPC error: ${error.message}`);
    }

    const metrics = data as DashboardMetrics;
    const topProduct = metrics?.top_products?.[0]?.product_name || null;
    
    return { topProduct };
}

test.describe('AI Response Accuracy vs. Database Ground Truth', () => {

  let groundTruth: { topProduct: string | null };

  test.beforeAll(async () => {
    // Fetch the ground truth from the database once before the tests run
    groundTruth = await getGroundTruth();
  });

  test('AI should correctly identify the top-selling product', async ({ page }) => {
    // Pre-condition: Ensure we have a top product to test against
    if (!groundTruth.topProduct) {
        test.skip(true, "Skipping test: No top product found in the database to verify against.");
        return;
    }
    
    console.log(`[Ground Truth] Top selling product is: "${groundTruth.topProduct}"`);

    // Navigate to the chat page
    await page.goto('/chat');
    await page.waitForURL('/chat');

    // Ask the AI a question about the top product
    const question = "What is my top selling product by revenue?";
    await page.locator('input[placeholder*="Ask anything"]').fill(question);
    await page.getByRole('button', { name: 'Send message' }).click();

    // Wait for the AI's response to appear
    const assistantMessageContainer = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
    await expect(assistantMessageContainer).toBeVisible({ timeout: 20000 });

    // Verify the AI's answer contains the name of the top product
    const aiResponseText = await assistantMessageContainer.innerText();
    console.log(`[AI Response] Received: "${aiResponseText}"`);
    
    await expect(assistantMessageContainer).toContainText(new RegExp(groundTruth.topProduct, 'i'), { timeout: 10000 });

    console.log(`[Test Result] PASS: AI correctly identified "${groundTruth.topProduct}" as the top product.`);
  });
});
