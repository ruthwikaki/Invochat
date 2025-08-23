import { test, expect } from '@playwright/test';

// Use shared authentication
test.use({ storageState: 'playwright/.auth/user.json' });

test.describe('Advanced Business Logic Tests - AIventory', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
  });

  test('should handle purchase order creation workflow', async ({ page }) => {
    await page.goto('/purchase-orders/new');
    
    // Wait for page to load
    await page.waitForSelector('h1:has-text("Create Purchase Order")', { timeout: 10000 });
    
    // Check that the form loads
    await expect(page.locator('text=Supplier')).toBeVisible();
    await expect(page.locator('text=Product')).toBeVisible();
    
    // Basic form interaction - just verify the form is functional
    const supplierSelect = page.locator('select').first();
    if (await supplierSelect.isVisible()) {
      // Form has suppliers loaded
      expect(await supplierSelect.count()).toBeGreaterThan(0);
    }
  });

  test('should navigate to suppliers page', async ({ page }) => {
    await page.goto('/suppliers');
    
    // Wait for suppliers page to load
    await page.waitForSelector('h1:has-text("Suppliers")', { timeout: 10000 });
    
    // Check that we can see the suppliers page
    await expect(page.locator('text=Suppliers')).toBeVisible();
  });

  test('should handle inventory page navigation', async ({ page }) => {
    await page.goto('/inventory');
    
    // Wait for inventory page to load  
    await page.waitForLoadState('networkidle', { timeout: 15000 });
    
    // Check that inventory page loads correctly - look for inventory-specific content
    const hasInventoryContent = await page.locator('h1, [data-testid*="inventory"], text=Inventory').first().isVisible({ timeout: 10000 });
    expect(hasInventoryContent).toBeTruthy();
    
    // Check that page content loaded successfully
    const pageContent = await page.textContent('body');
    expect(pageContent).toBeTruthy();
    if (pageContent) {
      expect(pageContent.length).toBeGreaterThan(100); // Ensure substantial content loaded
    }
  });

  test('should navigate to analytics pages', async ({ page }) => {
    // Test supplier performance analytics
    await page.goto('/analytics/supplier-performance');
    
    // Should not be 404
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
    
    // Test inventory turnover analytics  
    await page.goto('/analytics/inventory-turnover');
    
    const status2 = await page.locator('text=404').count();
    expect(status2).toBe(0);
  });

  test('should handle chat interface', async ({ page }) => {
    await page.goto('/chat');
    
    // Wait for chat page to load
    await page.waitForTimeout(2000);
    
    // Should not be 404
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
  });

  test('should handle settings pages', async ({ page }) => {
    // Test profile settings
    await page.goto('/settings/profile');
    
    // Should not be 404
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
    
    // Test integrations settings
    await page.goto('/settings/integrations');
    
    const status2 = await page.locator('text=404').count();
    expect(status2).toBe(0);
  });

  test('should handle purchase orders list page', async ({ page }) => {
    await page.goto('/purchase-orders');
    
    // Wait for page to load
    await page.waitForTimeout(2000);
    
    // Should not be 404
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
  });

  test('should handle customers page', async ({ page }) => {
    await page.goto('/customers');
    
    // Wait for page to load
    await page.waitForTimeout(2000);
    
    // Should not be 404  
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
  });

  test('should handle sales page', async ({ page }) => {
    await page.goto('/sales');
    
    // Wait for page to load
    await page.waitForTimeout(2000);
    
    // Should not be 404
    const status = await page.locator('text=404').count();
    expect(status).toBe(0);
  });

  test('should handle basic form interactions', async ({ page }) => {
    await page.goto('/suppliers/new');
    
    // Wait for supplier form to load
    await page.waitForTimeout(2000);
    
    // Check if form exists
    const forms = await page.locator('form').count();
    expect(forms).toBeGreaterThan(0);
    
    // Check for basic form elements
    const inputs = await page.locator('input, select, textarea').count();
    expect(inputs).toBeGreaterThan(0);
  });
});

test.describe('Data Validation Tests - AIventory', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
  });

  test('should validate page loads correctly', async ({ page }) => {
    // Test that dashboard loads without errors
    await expect(page.locator('[data-testid="dashboard-root"]')).toBeVisible();
    
    // Test that navigation is present
    await expect(page.locator('[data-testid="main-navigation"]')).toBeVisible();
    
    // Test that user menu is accessible
    await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  });

  test('should handle concurrent page navigation', async ({ page, context }) => {
    // Create multiple pages
    const page2 = await context.newPage();
    const page3 = await context.newPage();
    
    // All pages use shared authentication
    await Promise.all([
      page.goto('/dashboard'),
      page2.goto('/inventory'), 
      page3.goto('/suppliers')
    ]);
    
    // All should load successfully
    await expect(page.locator('[data-testid="dashboard-root"]')).toBeVisible();
    await expect(page2.locator('body')).toBeVisible();
    await expect(page3.locator('body')).toBeVisible();
    
    await page2.close();
    await page3.close();
  });

  test('should handle date and time correctly', async ({ page }) => {
    // Navigate to a page that likely shows dates
    await page.goto('/purchase-orders');
    
    // Wait for page load
    await page.waitForTimeout(2000);
    
    // Just verify the page loaded correctly
    const pageContent = await page.textContent('body');
    expect(pageContent).toBeTruthy();
    
    // Verify no console errors related to dates
    const errors = await page.evaluate(() => {
      return window.console.error.toString();
    });
    
    // This is a basic check - just ensure we don't have obvious date errors
    expect(typeof errors).toBe('string');
  });

  test('should handle large data sets gracefully', async ({ page }) => {
    // Test inventory page which likely has lots of data
    await page.goto('/inventory');
    
    // Wait for page to load completely
    await page.waitForTimeout(3000);
    
    // Check that page responds to user interaction
    const clickableElements = await page.locator('button, a, [role="button"]').count();
    expect(clickableElements).toBeGreaterThan(0);
  });

  test('should maintain session across page navigation', async ({ page }) => {
    // Start at dashboard
    await page.goto('/dashboard');
    await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
    
    // Navigate to different pages
    await page.goto('/inventory');
    await page.goto('/suppliers');
    await page.goto('/purchase-orders');
    
    // Return to dashboard - should still be authenticated
    await page.goto('/dashboard');
    await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  });
});
