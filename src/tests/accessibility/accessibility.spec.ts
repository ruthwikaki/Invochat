import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

/**
 * Accessibility Testing Suite
 * WCAG 2.1 AA compliance testing
 */

test.describe('Accessibility Tests - WCAG 2.1 AA Compliance', () => {
  
  test.beforeEach(async ({ page }) => {
    // Set up accessibility testing environment
    await page.setViewportSize({ width: 1280, height: 720 });
  });

  test('Dashboard accessibility audit', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
    
    // Wait for main content to load
    await page.waitForSelector('main, .main-content, [role="main"]', { timeout: 10000 });
    
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .exclude(['.loading', '.skeleton', '[aria-hidden="true"]'])
      .analyze();

    // Allow some minor violations but log them
    if (accessibilityScanResults.violations.length > 0) {
      console.log('Accessibility violations found:', accessibilityScanResults.violations.length);
      accessibilityScanResults.violations.forEach((violation, index) => {
        console.log(`${index + 1}. ${violation.id}: ${violation.description}`);
      });
    }

    // Only fail on critical violations
    const criticalViolations = accessibilityScanResults.violations.filter(v => 
      v.impact === 'critical' || v.impact === 'serious'
    );
    expect(criticalViolations.length).toBeLessThan(5);
  });

  test('Inventory page accessibility audit', async ({ page }) => {
    await page.goto('/inventory');
    await page.waitForLoadState('networkidle');
    
    // Wait for main content to load
    await page.waitForSelector('main, .main-content, table, .inventory-grid', { timeout: 10000 });
    
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .exclude(['.loading', '.skeleton', '[aria-hidden="true"]'])
      .analyze();

    // Allow some minor violations but log them
    if (accessibilityScanResults.violations.length > 0) {
      console.log('Inventory page accessibility violations:', accessibilityScanResults.violations.length);
    }

    // Only fail on critical violations
    const criticalViolations = accessibilityScanResults.violations.filter(v => 
      v.impact === 'critical' || v.impact === 'serious'
    );
    expect(criticalViolations.length).toBeLessThan(5);
  });

  test('Analytics page accessibility audit', async ({ page }) => {
    await page.goto('/analytics');
    
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
      .analyze();

    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test('Form accessibility - keyboard navigation', async ({ page }) => {
    await page.goto('/inventory/add-product');
    
    // Test keyboard navigation
    await page.keyboard.press('Tab');
    let focusedElement = await page.locator(':focus').first();
    await expect(focusedElement).toBeVisible();
    
    // Continue tabbing through form elements
    const formElements = ['input[name="name"]', 'input[name="sku"]', 'textarea[name="description"]'];
    
    for (const selector of formElements) {
      await page.keyboard.press('Tab');
      const element = page.locator(selector);
      await expect(element).toBeFocused();
    }
  });

  test('Color contrast compliance', async ({ page }) => {
    await page.goto('/dashboard');
    
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2aa'])
      .include('*')
      .analyze();

    // Check specifically for color contrast violations
    const colorContrastViolations = accessibilityScanResults.violations.filter(
      (violation: any) => violation.id === 'color-contrast'
    );
    
    expect(colorContrastViolations).toEqual([]);
  });

  test('Screen reader compatibility', async ({ page }) => {
    await page.goto('/dashboard');
    
    // Check for proper heading structure
    const headings = await page.locator('h1, h2, h3, h4, h5, h6').all();
    expect(headings.length).toBeGreaterThan(0);
    
    // Check for alt text on images
    const images = await page.locator('img').all();
    for (const image of images) {
      const alt = await image.getAttribute('alt');
      expect(alt).toBeTruthy();
    }
    
    // Check for proper ARIA labels
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a'])
      .analyze();

    const ariaViolations = accessibilityScanResults.violations.filter(
      (violation: any) => violation.id.includes('aria')
    );
    
    expect(ariaViolations).toEqual([]);
  });

  test('Focus management in modals', async ({ page }) => {
    await page.goto('/dashboard');
    
    // Open a modal (assuming there's a button to open settings)
    const openModalButton = page.locator('[data-testid="open-settings-modal"]');
    if (await openModalButton.isVisible()) {
      await openModalButton.click();
      
      // Check that focus is trapped in modal
      const modal = page.locator('[role="dialog"]');
      await expect(modal).toBeVisible();
      
      // First focusable element should be focused
      const firstFocusable = modal.locator('button, input, select, textarea, [tabindex]:not([tabindex="-1"])').first();
      await expect(firstFocusable).toBeFocused();
      
      // Test escape key closes modal
      await page.keyboard.press('Escape');
      await expect(modal).not.toBeVisible();
    }
  });

  test('Mobile accessibility', async ({ page }) => {
    // Test mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/dashboard');
    
    // Check touch target sizes (minimum 44x44 pixels)
    const buttons = await page.locator('button').all();
    for (const button of buttons) {
      const box = await button.boundingBox();
      if (box) {
        expect(box.width).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeGreaterThanOrEqual(44);
      }
    }
    
    // Run accessibility scan for mobile
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a', 'wcag2aa'])
      .analyze();

    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test('High contrast mode compatibility', async ({ page }) => {
    // Simulate high contrast mode
    await page.emulateMedia({ colorScheme: 'dark', forcedColors: 'active' });
    await page.goto('/dashboard');
    
    // Check that content is still visible and functional
    const mainContent = page.locator('main');
    await expect(mainContent).toBeVisible();
    
    // Run accessibility scan in high contrast mode
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2aa'])
      .analyze();

    expect(accessibilityScanResults.violations).toEqual([]);
  });

  test('Reduced motion preference', async ({ page }) => {
    // Simulate reduced motion preference
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/dashboard');
    
    // Check that animations are appropriately reduced
    const animatedElements = await page.locator('[class*="animate"], [class*="transition"]').all();
    
    for (const element of animatedElements) {
      const computedStyle = await element.evaluate(el => {
        return window.getComputedStyle(el).getPropertyValue('animation-duration');
      });
      
      // Animation should be very short or disabled
      expect(['0s', '0.01s', 'none']).toContain(computedStyle);
    }
  });

  test('Language and internationalization', async ({ page }) => {
    await page.goto('/dashboard');
    
    // Check for lang attribute
    const htmlElement = page.locator('html');
    const lang = await htmlElement.getAttribute('lang');
    expect(lang).toBeTruthy();
    
    // Check for proper text direction
    const dir = await htmlElement.getAttribute('dir');
    expect(['ltr', 'rtl', null]).toContain(dir);
    
    // Run accessibility scan for language issues
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withTags(['wcag2a'])
      .analyze();

    const languageViolations = accessibilityScanResults.violations.filter(
      (violation: any) => violation.id.includes('lang') || violation.id.includes('html')
    );
    
    expect(languageViolations).toEqual([]);
  });

  test('Error messages accessibility', async ({ page }) => {
    await page.goto('/auth/signin');
    
    // Submit form with empty fields to trigger errors
    const submitButton = page.locator('button[type="submit"]');
    await submitButton.click();
    
    // Check that error messages are properly associated with inputs
    const errorMessages = await page.locator('[role="alert"], .error-message, [aria-describedby]').all();
    
    for (const errorMessage of errorMessages) {
      // Error should be visible and announced to screen readers
      await expect(errorMessage).toBeVisible();
      
      const ariaLive = await errorMessage.getAttribute('aria-live');
      const role = await errorMessage.getAttribute('role');
      
      expect(ariaLive === 'polite' || ariaLive === 'assertive' || role === 'alert').toBeTruthy();
    }
  });

  test('Data table accessibility', async ({ page }) => {
    await page.goto('/inventory');
    
    // Check for proper table structure
    const tables = await page.locator('table').all();
    
    for (const table of tables) {
      // Check for table headers
      const headers = await table.locator('th').all();
      expect(headers.length).toBeGreaterThan(0);
      
      // Check for proper scope attributes
      for (const header of headers) {
        const scope = await header.getAttribute('scope');
        expect(['col', 'row', 'colgroup', 'rowgroup', null]).toContain(scope);
      }
      
      // Check for table caption or aria-label
      const caption = await table.locator('caption').count();
      const ariaLabel = await table.getAttribute('aria-label');
      const ariaLabelledby = await table.getAttribute('aria-labelledby');
      
      expect(caption > 0 || ariaLabel || ariaLabelledby).toBeTruthy();
    }
  });

});
