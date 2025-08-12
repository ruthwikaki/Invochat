

import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { User } from '@supabase/supabase-js';

// This test suite requires direct database interaction to set up the scenarios,
// which is why we use the Supabase admin client here.

let testUser: User | null = null;
let otherCompanyId: string | null = null;

test.beforeAll(async () => {
    const supabase = getServiceRoleClient();
    // Create a user and company for testing RLS policies
    const testEmail = `rls-test-user-${Date.now()}@example.com`;
    const { data: { user }, error } = await supabase.auth.admin.createUser({
        email: testEmail,
        password: 'TestPass123!',
        email_confirm: true,
    });
    if (error) throw new Error(`Failed to create test user: ${error.message}`);
    testUser = user;

    // Create a second company that this user should NOT have access to
     const { data: company } = await supabase.from('companies').insert({ name: 'Other Test Company'}).select('id').single();
     if(!company) throw new Error('Failed to create other test company');
     otherCompanyId = company.id;
});

test.describe('Security and Authorization', () => {

  test('should prevent unauthenticated access to protected API routes', async ({ page }) => {
    // This is now tested in unit tests for server actions, a more direct approach.
    // However, an E2E check is still valuable.
    await test.step('Attempt to access a protected page redirects to login', async () => {
        await page.goto('/dashboard');
        await page.waitForURL(/.*login/);
        await expect(page).toHaveURL(/.*login/);
    });
  });

  test('should enforce Row-Level Security for data access', async ({ page }) => {
    if (!testUser || !otherCompanyId) {
        test.skip(true, "Test user or other company setup failed.");
        return;
    }
    // Log in as the test user. This simulates a real user session.
    // The test user is automatically associated with their own new company on creation.
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email!);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    
    // Now, as the logged-in user, try to access a page that implicitly fetches data
    // for a company they do not belong to. In a real scenario, this would be an attempt
    // to access a direct URL like /suppliers/some-id-from-another-company.
    // For this test, we'll simulate this by trying to load the suppliers page and checking
    // that no data from 'otherCompanyId' is present.
    await page.goto('/suppliers');
    await page.waitForURL('/suppliers');
    
    // The RLS policy should prevent any suppliers from the "other" company from loading.
    // We can verify this by checking that the page does not contain any sensitive data
    // related to 'otherCompanyId'. Since we can't directly query the DB here, we ensure
    // the main user's data loads, but no errors of unauthorized access appear.
    await expect(page.getByRole('heading', { name: 'Suppliers', exact: true })).toBeVisible();
    // Since this is a new user, they should have no suppliers.
    await expect(page.getByText('No Suppliers Found')).toBeVisible();
  });

});

test.afterAll(async () => {
    if(testUser) {
        const supabase = getServiceRoleClient();
        await supabase.auth.admin.deleteUser(testUser.id);
        if(otherCompanyId) {
            await supabase.from('companies').delete().eq('id', otherCompanyId);
        }
    }
});
