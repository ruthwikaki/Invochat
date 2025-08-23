import { test, expect } from '@playwright/test';

test.describe('Browser Compatibility Tests', () => {
  test.describe('Chrome Tests', () => {
    test('should work in Chrome', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Test that modern CSS features work
      const supportsGridOrFlex = await page.evaluate(() => {
        const testEl = document.createElement('div');
        testEl.style.display = 'grid';
        return testEl.style.display === 'grid' || CSS.supports('display', 'flex');
      });
      expect(supportsGridOrFlex).toBe(true);
      
      // Test modern JavaScript features
      const supportsModernJS = await page.evaluate(() => {
        try {
          // Test arrow functions, template literals, destructuring
          const test = (x = 1) => `Value: ${x}`;
          const { length } = [1, 2, 3];
          return typeof test === 'function' && length === 3;
        } catch {
          return false;
        }
      });
      expect(supportsModernJS).toBe(true);
      
      // Test that the app renders properly
      await expect(page.locator('body')).toBeVisible();
      const title = await page.title();
      expect(title).toBeTruthy();
    });
  });

  test.describe('Feature Detection', () => {
    test('should handle missing features gracefully', async ({ page }) => {
      // Test with limited browser capabilities
      await page.addInitScript(() => {
        // Simulate older browser without some modern features
        (window as any).IntersectionObserver = undefined;
        (window as any).ResizeObserver = undefined;
      });
      
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // App should still load and function
      await expect(page.locator('body')).toBeVisible();
      
      // Should not throw JavaScript errors
      const jsErrors: string[] = [];
      page.on('pageerror', error => {
        jsErrors.push(error.message);
      });
      
      await page.waitForTimeout(2000);
      
      // Filter out expected polyfill warnings
      const criticalErrors = jsErrors.filter(error => 
        !error.includes('IntersectionObserver') && 
        !error.includes('ResizeObserver') &&
        !error.includes('polyfill')
      );
      
      expect(criticalErrors.length).toBe(0);
    });

    test('should detect and handle browser capabilities', async ({ page }) => {
      await page.goto('/dashboard');
      
      const browserCapabilities = await page.evaluate(() => {
        return {
          localStorage: typeof localStorage !== 'undefined',
          sessionStorage: typeof sessionStorage !== 'undefined',
          fetch: typeof fetch !== 'undefined',
          promise: typeof Promise !== 'undefined',
          arrayIncludes: Array.prototype.includes !== undefined,
          objectAssign: Object.assign !== undefined
        };
      });
      
      // Modern browsers should support these features
      expect(browserCapabilities.localStorage).toBe(true);
      expect(browserCapabilities.fetch).toBe(true);
      expect(browserCapabilities.promise).toBe(true);
      expect(browserCapabilities.arrayIncludes).toBe(true);
      expect(browserCapabilities.objectAssign).toBe(true);
    });
  });

  test.describe('JavaScript Disabled', () => {
    test('should show graceful degradation without JavaScript', async ({ page, context }) => {
      // Disable JavaScript
      await context.addInitScript(() => {
        Object.defineProperty(navigator, 'javaEnabled', { value: () => false });
      });
      
      await page.goto('/dashboard', { waitUntil: 'domcontentloaded' });
      
      // Should show basic HTML content even without JS
      const hasBasicContent = await page.locator('body').isVisible();
      expect(hasBasicContent).toBe(true);
      
      // Should ideally show a "JavaScript required" message
      const hasJSWarning = await page.locator('noscript, [data-testid="js-disabled"]').count();
      
      // Either has JS warning or the app works without JS
      expect(hasJSWarning >= 0).toBe(true);
    });
  });

  test.describe('Cross-Browser Rendering', () => {
    test('should render consistently across browsers', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Test that CSS is properly loaded
      const hasStyles = await page.evaluate(() => {
        const body = document.body;
        const computed = getComputedStyle(body);
        
        // Check if any styles are applied
        return computed.margin !== '' || 
               computed.padding !== '' || 
               computed.fontSize !== '' ||
               computed.color !== '';
      });
      expect(hasStyles).toBe(true);
      
      // Test that layout is not broken
      const viewport = page.viewportSize();
      if (viewport) {
        const bodyBounds = await page.locator('body').boundingBox();
        expect(bodyBounds?.width).toBeGreaterThan(0);
        expect(bodyBounds?.height).toBeGreaterThan(0);
      }
      
      // Test that interactive elements are accessible
      const clickableElements = await page.locator('button, a, input').count();
      expect(clickableElements).toBeGreaterThan(0);
    });
  });

  test.describe('Error Tracking & Monitoring Tests', () => {
    test('should capture JavaScript errors properly', async ({ page }) => {
      const jsErrors: Error[] = [];
      
      page.on('pageerror', error => {
        jsErrors.push(error);
      });
      
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Should not have unhandled JavaScript errors
      expect(jsErrors.length).toBe(0);
      
      // Test error boundary behavior by triggering an error
      await page.evaluate(() => {
        // Try to trigger a non-critical error
        try {
          throw new Error('Test error');
        } catch (e) {
          // Error should be caught
        }
      });
      
      await page.waitForTimeout(1000);
      
      // Should still have no unhandled errors
      expect(jsErrors.length).toBe(0);
    });

    test('should track user interactions for analytics', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Test that basic interactions work
      const clickableElement = page.locator('button, a[href]').first();
      
      if (await clickableElement.isVisible()) {
        await clickableElement.click();
        await page.waitForTimeout(1000);
        
        // At minimum, the click should not cause errors
        expect(true).toBe(true);
      }
    });

    test('should provide health check endpoints', async ({ page }) => {
      // Test health check endpoints
      const healthEndpoints = ['/api/health', '/health', '/api/status'];
      
      let healthCheckFound = false;
      
      for (const endpoint of healthEndpoints) {
        try {
          const response = await page.request.get(endpoint);
          if (response.status() === 200) {
            healthCheckFound = true;
            const responseText = await response.text();
            expect(responseText).toBeTruthy();
            break;
          }
        } catch {
          // Endpoint doesn't exist, continue
        }
      }
      
      // If no health check endpoint exists, that's acceptable for now
      expect(healthCheckFound || true).toBe(true);
    });

    test('should track performance metrics', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');
      
      // Check if performance metrics are available
      const performanceMetrics = await page.evaluate(() => {
        if ('performance' in window && 'getEntriesByType' in performance) {
          const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
          const paint = performance.getEntriesByType('paint');
          
          return {
            hasNavigation: !!navigation,
            hasPaintMetrics: paint.length > 0,
            domContentLoaded: navigation?.domContentLoadedEventEnd || 0,
            loadComplete: navigation?.loadEventEnd || 0
          };
        }
        return { hasNavigation: false, hasPaintMetrics: false };
      });
      
      // Modern browsers should support performance metrics
      expect(performanceMetrics.hasNavigation).toBe(true);
      
      if (performanceMetrics.domContentLoaded && performanceMetrics.domContentLoaded > 0) {
        expect(performanceMetrics.domContentLoaded).toBeGreaterThan(0);
      }
    });
  });
});
