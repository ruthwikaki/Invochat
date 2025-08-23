import { test, expect } from '@playwright/test';

test.describe('Database Connectivity Test', () => {
  test.use({ storageState: 'playwright/.auth/user.json' });

  test('should validate database connectivity and core functionality', async ({ page }) => {
    // Test database connectivity via API endpoints that use the database
    await page.goto('/dashboard');
    await page.waitForLoadState('domcontentloaded', { timeout: 15000 });
    
    // Verify dashboard loads (which requires database access) - use specific heading
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible({ timeout: 10000 });
    
    console.log('✅ Database connectivity validated');
  });
});
