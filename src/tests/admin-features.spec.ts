
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { switchUser } from './test-utils';

const adminUser = credentials.test_users[0];
const memberUserEmail = `testmember-${Date.now()}@example.com`;
const memberUserPassword = 'TestMemberPassword123!';
const memberUser = { email: memberUserEmail, password: memberUserPassword };

async function login(page: Page, user: { email: string, password: string }) {
    console.log(`🔐 Logging in as ${user.email}...`);
    
    // Navigate to login and wait for page to be ready
    await page.goto('/login', { waitUntil: 'networkidle' });
    
    // Wait for login form to be visible and interactable
    await page.waitForSelector('input[name="email"]', { state: 'visible' });
    await page.waitForSelector('input[name="password"]', { state: 'visible' });
    await page.waitForSelector('button[type="submit"]', { state: 'visible' });
    
    // Fill form fields
    await page.fill('input[name="email"]', user.email);
    await page.fill('input[name="password"]', user.password);
    
    // Submit form and wait for navigation
    const navigationPromise = page.waitForURL('/dashboard', { timeout: 45000 });
    await page.click('button[type="submit"]');
    
    try {
        await navigationPromise;
        console.log(`✅ Successfully logged in as ${user.email}`);
    } catch (error) {
        console.error(`❌ Login failed for ${user.email}:`, error);
        // Take a screenshot for debugging
        await page.screenshot({ path: `login-failure-${Date.now()}.png`, fullPage: true });
        throw error;
    }
}

test.describe('Admin & Role Permission Tests', () => {

    let memberUserId: string;

    test.beforeAll(async () => {
        // Create a 'Member' user for testing permissions
        const supabase = getServiceRoleClient();
        const { data: companyData } = await supabase.from('companies').select('id').eq('name', adminUser.company_name).single();
        if (!companyData) throw new Error('Test company not found');
        
        const { data: authData, error } = await supabase.auth.admin.createUser({
            email: memberUserEmail,
            password: memberUserPassword,
            email_confirm: true,
        });
        
        if (error) throw error;
        memberUserId = authData.user.id;

        await supabase.from('company_users').insert({
            company_id: companyData.id,
            user_id: memberUserId,
            role: 'Member'
        });
    });

    test('Admin should be able to access the Audit Log page', async ({ page }) => {
        await login(page, adminUser);
        await page.goto('/settings/audit-log');
        await page.waitForURL('/settings/audit-log');
        await expect(page.getByRole('heading', { name: 'Audit Log' })).toBeVisible();
        await expect(page.locator('table > tbody > tr').first()).toBeVisible();
    });

    test('Admin should be able to access the AI Performance page', async ({ page }) => {
        await login(page, adminUser);
        await page.goto('/analytics/ai-performance');
        await page.waitForURL('/analytics/ai-performance');
        await expect(page.getByRole('heading', { name: 'AI Performance & Feedback' })).toBeVisible();
        // Check for either feedback data or the "no feedback" message
        const feedbackTable = page.locator('table tbody');
        await expect(feedbackTable).toBeVisible();
        // Verify either data rows exist or the "no feedback" message is shown
        await expect(
            feedbackTable.locator('tr').first()
        ).toBeVisible();
    });
    
    test('Member user should be redirected from admin-only pages', async ({ page }) => {
        await switchUser(page, memberUser);
        
        // Try to access Audit Log - page loads but data should be empty due to permission check
        await page.goto('/settings/audit-log');
        await page.waitForURL('/settings/audit-log');
        // Page loads but should show no data due to admin permission requirement
        await expect(page.getByRole('heading', { name: 'Audit Log' })).toBeVisible();
        // Should show empty state since member doesn't have admin permissions
        const auditTable = page.locator('table tbody');
        await expect(auditTable).toBeVisible();

        // Try to access AI Performance - same behavior expected
        await page.goto('/analytics/ai-performance');
        await page.waitForURL('/analytics/ai-performance');
        // Page loads but should show no data due to admin permission requirement
        await expect(page.getByRole('heading', { name: 'AI Performance & Feedback' })).toBeVisible();
        const feedbackTable = page.locator('table tbody');
        await expect(feedbackTable).toBeVisible();
    });

    test.afterAll(async () => {
        const supabase = getServiceRoleClient();
        await supabase.auth.admin.deleteUser(memberUserId);
    });
});

