import { test, expect } from '@playwright/test';
import credentials from './test_data/test_credentials.json';
import { formatCentsAsCurrency } from '@/lib/utils';
import { getServiceRoleClient } from '@/lib/supabase/admin';

const testUser = credentials.test_users[0];

// Helper to get a specific stat from the database to verify against the UI
async function getDbStat(companyId: string, statName: 'total_revenue' | 'total_orders' | 'new_customers') {
    const supabase = getServiceRoleClient();
    const { data } = await supabase.rpc('get_dashboard_metrics', {
        p_company_id: companyId,
        p_days: 90
    });
    return data ? data[statName] : 0;
}

test.describe('Real Data End-to-End Tests', () => {

  test('should login and verify that generated data appears correctly on key pages', async ({ page }) => {
    // 1. LOGIN
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    console.log('✅ Login successful, on dashboard.');

    const supabase = getServiceRoleClient();
    const { data: company } = await supabase.from('companies').select('id').eq('name', testUser.company_name).single();
    expect(company).not.toBeNull();
    const companyId = company!.id;

    // 2. VERIFY DASHBOARD
    const expectedRevenue = await getDbStat(companyId, 'total_revenue');
    const expectedRevenueString = formatCentsAsCurrency(expectedRevenue);
    
    await expect(page.getByTestId('total-revenue-card')).toContainText(expectedRevenueString, { timeout: 15000 });
    console.log(`✅ Dashboard revenue verified: ${expectedRevenueString}`);

    // 3. VERIFY INVENTORY PAGE
    await page.goto('/inventory');
    await page.waitForURL('/inventory');
    const products = await page.locator('table[data-testid="inventory-table"] tbody tr').count();
    expect(products).toBeGreaterThan(0);
    console.log(`✅ Inventory page shows ${products} products.`);

    // 4. VERIFY CUSTOMERS PAGE
    await page.goto('/customers');
    await page.waitForURL('/customers');
    const customers = await page.locator('table[data-testid="customers-table"] tbody tr').count();
    expect(customers).toBeGreaterThan(0);
    const firstCustomerEmail = await page.locator('table[data-testid="customers-table"] tbody tr').first().locator('td').nth(0).innerText();
    expect(firstCustomerEmail).toContain('@');
    console.log(`✅ Customers page shows ${customers} customers. First email: ${firstCustomerEmail}`);
  });
});
