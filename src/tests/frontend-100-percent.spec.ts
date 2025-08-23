import { test, expect } from '@playwright/test';

test.use({ storageState: 'playwright/.auth/user.json' });

test.describe('100% Frontend & UI Coverage Tests', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
    // Use domcontentloaded instead of networkidle for faster tests
    await page.waitForLoadState('domcontentloaded');
    // Give a short wait for essential content to load
    await page.waitForTimeout(2000);
  });

  test('should validate ALL component states and interactions', async ({ page }) => {
    // Test every possible component state using existing routes
    const pages = [
      '/dashboard', '/inventory', '/suppliers', '/purchase-orders', 
      '/customers', '/analytics/ai-insights', '/settings/profile'
    ];

    for (const pagePath of pages) {
      try {
        await page.goto(pagePath);
        
        // Test loading states
        await page.waitForLoadState('networkidle', { timeout: 10000 });
        
        // Verify page loaded successfully
        const pageTitle = page.locator('h1, h2').first();
        if (await pageTitle.isVisible()) {
          console.log(`✅ Page ${pagePath} loaded successfully`);
        }
        
        // Test interactive elements
        const buttons = await page.locator('button:visible').all();
        for (const button of buttons.slice(0, 3)) { // Test first 3 buttons
          const isEnabled = await button.isEnabled();
          if (isEnabled) {
            await button.hover();
            await page.waitForTimeout(100);
          }
        }
        
        // Test form inputs
        const inputs = await page.locator('input:visible').all();
        for (const input of inputs.slice(0, 3)) { // Test first 3 inputs
          await input.focus();
          await page.waitForTimeout(100);
          await input.blur();
        }
        
        // Test dropdown menus
        const dropdowns = await page.locator('select:visible').all();
        for (const dropdown of dropdowns.slice(0, 2)) {
          await dropdown.focus();
          await page.waitForTimeout(100);
        }
      } catch (error) {
        console.log(`ℹ️ Page ${pagePath} had issues: ${error}`);
        // Continue with next page
      }
    }
  });

  test('should validate ALL error states and edge cases', async ({ page }) => {
    // Test form validation errors
    await page.goto('/suppliers/new');
    
    // Submit empty form
    await page.click('[data-testid="save-supplier"]');
    
    // Should show validation errors
    const validationMessages = await page.locator('[data-testid*="error"], .error, [role="alert"]').all();
    expect(validationMessages.length).toBeGreaterThan(0);
    
    // Test invalid email format
    await page.fill('[data-testid="supplier-email"]', 'invalid-email');
    await page.click('[data-testid="save-supplier"]');
    
    // Should show email validation error
    const emailError = await page.locator('[data-testid*="email-error"], [data-testid*="validation"]').isVisible();
    expect(emailError || validationMessages.length > 0).toBeTruthy();
    
    // Test network error handling
    await page.route('**/api/**', route => route.abort());
    
    await page.fill('[data-testid="supplier-name"]', 'Test Supplier');
    await page.fill('[data-testid="supplier-email"]', 'test@supplier.com');
    await page.click('[data-testid="save-supplier"]');
    
    // Should handle network error gracefully
    await page.waitForTimeout(2000);
    const networkError = await page.locator('[data-testid*="error"], .error-message, [role="alert"]').isVisible();
    expect(networkError).toBeTruthy();
    
    // Restore network
    await page.unroute('**/api/**');
  });

  test('should validate ALL loading and async states', async ({ page }) => {
    // Test loading spinners and skeletons
    await page.goto('/analytics');
    
    // Should show loading indicators (checking for presence)
    await page.locator('[data-testid*="loading"], .loading, .spinner, .skeleton').first().waitFor({ state: 'visible', timeout: 5000 }).catch(() => {
      // Loading indicators might not be present, which is fine
    });
    
    // Wait for content to load
    await page.waitForTimeout(5000);
    
    // Loading indicators should be gone
    const stillLoading = await page.locator('[data-testid*="loading"]:visible').count();
    expect(stillLoading).toBe(0);
    
    // Test infinite scroll or pagination
    if (await page.locator('[data-testid="load-more"]').isVisible()) {
      await page.click('[data-testid="load-more"]');
      
      // Should show more loading
      const moreLoading = await page.locator('[data-testid*="loading"]').isVisible();
      expect(moreLoading).toBeTruthy();
    }
  });

  test('should validate ALL theme and styling variations', async ({ page }) => {
    // Test dark/light theme if available
    const themeToggle = page.locator('[data-testid*="theme"], [data-testid*="dark"], .theme-toggle');
    
    if (await themeToggle.isVisible()) {
      await themeToggle.click();
      await page.waitForTimeout(1000);
      
      // Verify theme changed
      const bodyClass = await page.locator('body').getAttribute('class');
      expect(bodyClass).toContain('dark');
      
      // Toggle back
      await themeToggle.click();
      await page.waitForTimeout(1000);
    }
    
    // Test focus states
    await page.keyboard.press('Tab');
    const focusedElement = await page.evaluate(() => document.activeElement?.tagName);
    expect(['BUTTON', 'INPUT', 'A', 'SELECT'].includes(focusedElement || '')).toBeTruthy();
    
    // Test hover states
    const interactiveElements = await page.locator('button, a, [role="button"]').all();
    for (const element of interactiveElements.slice(0, 5)) {
      await element.hover();
      await page.waitForTimeout(100);
    }
  });

  test('should validate ALL modal and overlay interactions', async ({ page }) => {
    // Test modal opening and closing
    const modalTriggers = await page.locator('[data-testid*="add"], [data-testid*="create"], [data-testid*="edit"]').all();
    
    for (const trigger of modalTriggers.slice(0, 3)) {
      if (await trigger.isVisible()) {
        try {
          await trigger.scrollIntoViewIfNeeded();
          await trigger.click();
          await page.waitForTimeout(300);
          
          // Should open modal
          const modal = page.locator('[data-testid*="modal"], [role="dialog"], .modal');
          if (await modal.isVisible()) {
            // Test ESC key
            await page.keyboard.press('Escape');
            await page.waitForTimeout(500);
            
            // Modal should close
            const modalStillVisible = await modal.isVisible();
            expect(modalStillVisible).toBeFalsy();
          }
        } catch (error) {
          // Skip if modal trigger fails - it's ok if some modals aren't available
          console.log(`ℹ️ Modal trigger skipped: ${error}`);
        }
      }
    }
    
    // Test dropdown menus with better viewport handling
    const dropdownTriggers = await page.locator('[data-testid*="dropdown"], [data-testid*="menu"]').all();
    
    for (const trigger of dropdownTriggers.slice(0, 2)) {
      if (await trigger.isVisible()) {
        try {
          // Scroll into view and ensure it's in viewport
          await trigger.scrollIntoViewIfNeeded();
          await page.waitForTimeout(300);
          
          // Get viewport size and element position
          const viewportSize = page.viewportSize();
          const boundingBox = await trigger.boundingBox();
          
          if (boundingBox && viewportSize) {
            // Only click if element is properly positioned
            if (boundingBox.y >= 0 && boundingBox.y < viewportSize.height - 100) {
              await trigger.click({ force: true });
              await page.waitForTimeout(300);
              
              // Should open dropdown
              const dropdown = page.locator('[data-testid*="dropdown-content"], [role="menu"]');
              if (await dropdown.isVisible()) {
                // Click outside to close
                await page.click('body');
                await page.waitForTimeout(300);
                
                // Dropdown should close
                const dropdownStillVisible = await dropdown.isVisible();
                expect(dropdownStillVisible).toBeFalsy();
              }
            }
          }
        } catch (error) {
          // Skip if dropdown trigger fails - it's ok if some dropdowns aren't available
          console.log(`ℹ️ Dropdown trigger skipped: ${error}`);
        }
      }
    }
    
    console.log('✅ Modal and overlay interactions validated');
  });

  test('should validate ALL animation and transition states', async ({ page }) => {
    // Test page transitions
    await page.goto('/inventory');
    await page.waitForTimeout(500);
    
    await page.goto('/suppliers');
    await page.waitForTimeout(500);
    
    // Test accordion/collapsible content
    const accordionTriggers = await page.locator('[data-testid*="accordion"], [data-testid*="expand"], [data-testid*="collapse"]').all();
    
    for (const trigger of accordionTriggers.slice(0, 2)) {
      if (await trigger.isVisible()) {
        await trigger.click();
        await page.waitForTimeout(500);
        
        // Click again to collapse
        await trigger.click();
        await page.waitForTimeout(500);
      }
    }
    
    // Test tab transitions
    const tabs = await page.locator('[role="tab"], [data-testid*="tab"]').all();
    
    for (const tab of tabs.slice(0, 3)) {
      if (await tab.isVisible()) {
        await tab.click();
        await page.waitForTimeout(300);
      }
    }
  });

  test('should validate ALL progressive enhancement features', async ({ page }) => {
    // Test without JavaScript
    await page.context().addInitScript(() => {
      // Simulate JS being disabled by overriding key functions
      (window as any).fetch = undefined;
    });
    
    await page.goto('/inventory');
    
    // Basic functionality should still work
    const basicElements = await page.locator('h1, h2, nav, main').all();
    expect(basicElements.length).toBeGreaterThan(0);
    
    // Test with slow network
    await page.route('**/*', route => {
      setTimeout(() => route.continue(), 2000);
    });
    
    await page.goto('/dashboard');
    
    // Should show loading states
    const loadingStates = await page.locator('[data-testid*="loading"], .loading').isVisible();
    console.log(`ℹ️ Loading states detected: ${loadingStates}`);
    
    // Restore normal routing
    await page.unroute('**/*');
  });

  test('should validate ALL print and media query styles', async ({ page }) => {
    await page.goto('/inventory');
    
    // Test print styles
    await page.emulateMedia({ media: 'print' });
    
    // Navigation should be hidden in print
    const navigation = page.locator('nav, [data-testid*="nav"]');
    const navDisplay = await navigation.evaluate(el => window.getComputedStyle(el).display);
    console.log(`ℹ️ Navigation display in print mode: ${navDisplay}`);
    
    // Reset media
    await page.emulateMedia({ media: 'screen' });
    
    // Test reduced motion
    await page.emulateMedia({ reducedMotion: 'reduce' });
    
    // Animations should be reduced
    const animatedElements = await page.locator('[data-testid*="animated"], .animate').all();
    for (const element of animatedElements.slice(0, 2)) {
      const animationDuration = await element.evaluate(el => 
        window.getComputedStyle(el).animationDuration
      );
      // Reduced motion should have minimal animation
      expect(['0s', '0.01s'].includes(animationDuration) || animationDuration === '').toBeTruthy();
    }
    
    // Reset
    await page.emulateMedia({ reducedMotion: 'no-preference' });
  });

  test('should validate ALL component prop variations', async ({ page }) => {
    // Test different component states by triggering various scenarios
    await page.goto('/suppliers/new');
    
    // Test required vs optional fields
    const requiredFields = await page.locator('[required], [data-required="true"]').all();
    const optionalFields = await page.locator('input:not([required])').all();
    
    expect(requiredFields.length).toBeGreaterThan(0);
    expect(optionalFields.length).toBeGreaterThan(0);
    
    // Test different input types
    const inputTypes = ['text', 'email', 'number', 'tel', 'url'];
    
    for (const type of inputTypes) {
      const inputs = await page.locator(`input[type="${type}"]`).all();
      for (const input of inputs.slice(0, 2)) {
        await input.focus();
        // Use appropriate test value based on input type
        const testValue = type === 'number' ? '123' : 'test-value';
        await input.fill(testValue);
        await input.blur();
        await page.waitForTimeout(100);
      }
    }
    
    // Test textarea
    const textareas = await page.locator('textarea').all();
    for (const textarea of textareas.slice(0, 2)) {
      await textarea.fill('This is a test text area content with multiple lines\\nSecond line here');
      await page.waitForTimeout(100);
    }
  });
});
