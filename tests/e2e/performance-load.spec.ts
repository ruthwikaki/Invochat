import { test, expect, Page } from '@playwright/test';

/**
 * Performance and Load Testing
 * Application performance validation
 */

test.describe('Performance & Load Tests', () => {
  let page: Page;

  test.beforeEach(async ({ page: testPage }) => {
    page = testPage;
    
    // Mock authentication
    await page.addInitScript(() => {
      localStorage.setItem('supabase.auth.token', JSON.stringify({
        access_token: 'mock-token',
        user: { id: 'test-user', email: 'test@example.com' }
      }));
    });
  });

  test('Dashboard load performance', async () => {
    const startTime = Date.now();
    
    // Navigate to dashboard
    await page.goto('/app/dashboard');
    
    // Wait for all critical elements to load
    await page.waitForSelector('[data-testid="dashboard-content"]');
    await page.waitForSelector('[data-testid="revenue-chart"]');
    await page.waitForSelector('[data-testid="inventory-metrics"]');
    
    const loadTime = Date.now() - startTime;
    
    // Dashboard should load within 3 seconds
    expect(loadTime).toBeLessThan(3000);
    
    // Check for performance metrics
    const performanceEntries = await page.evaluate(() => {
      return JSON.stringify(performance.getEntriesByType('navigation'));
    });
    
    const entries = JSON.parse(performanceEntries);
    const navigationEntry = entries[0];
    
    // DOM content should load quickly
    expect(navigationEntry.domContentLoadedEventEnd - navigationEntry.domContentLoadedEventStart).toBeLessThan(1500);
  });

  test('Large dataset handling', async () => {
    // Navigate to inventory with large dataset
    await page.goto('/app/inventory');
    
    // Simulate large inventory dataset
    await page.evaluate(() => {
      // Mock large dataset response
      (window as any).__TEST_LARGE_DATASET__ = true;
    });
    
    const startTime = Date.now();
    
    // Wait for grid to load
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    // Check that grid renders within reasonable time
    const renderTime = Date.now() - startTime;
    expect(renderTime).toBeLessThan(5000);
    
    // Test pagination performance
    await page.click('[data-testid="next-page"]');
    const paginationStart = Date.now();
    
    await page.waitForSelector('[data-testid="inventory-grid"]:not([data-loading="true"])');
    const paginationTime = Date.now() - paginationStart;
    
    // Pagination should be fast
    expect(paginationTime).toBeLessThan(2000);
  });

  test('Memory usage monitoring', async () => {
    // Navigate to dashboard
    await page.goto('/app/dashboard');
    await page.waitForSelector('[data-testid="dashboard-content"]');
    
    // Get initial memory usage
    const initialMemory = await page.evaluate(() => {
      return (performance as any).memory?.usedJSHeapSize || 0;
    });
    
    // Navigate through multiple pages to test memory leaks
    const pages = [
      '/app/inventory',
      '/app/suppliers',
      '/app/purchase-orders',
      '/app/sales',
      '/app/dashboard/analytics'
    ];
    
    for (const pagePath of pages) {
      await page.goto(pagePath);
      await page.waitForTimeout(1000); // Allow page to fully load
    }
    
    // Force garbage collection if available
    await page.evaluate(() => {
      if ((window as any).gc) {
        (window as any).gc();
      }
    });
    
    // Get final memory usage
    const finalMemory = await page.evaluate(() => {
      return (performance as any).memory?.usedJSHeapSize || 0;
    });
    
    // Memory increase should be reasonable (less than 50MB)
    const memoryIncrease = finalMemory - initialMemory;
    expect(memoryIncrease).toBeLessThan(50 * 1024 * 1024);
  });

  test('API response times', async () => {
    await page.goto('/app/dashboard');
    
    // Monitor API calls
    const apiCalls: Array<{ url: string, duration: number }> = [];
    
    page.on('response', async (response) => {
      if (response.url().includes('/api/')) {
        const request = response.request();
        const timing = request.timing();
        apiCalls.push({
          url: response.url(),
          duration: timing.responseEnd - timing.responseStart
        });
      }
    });
    
    // Trigger API calls by navigating to different sections
    await page.click('[data-testid="analytics-nav"]');
    await page.waitForSelector('[data-testid="analytics-content"]');
    
    await page.click('[data-testid="inventory-nav"]');
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    // Wait for all API calls to complete
    await page.waitForTimeout(2000);
    
    // Verify API response times
    for (const call of apiCalls) {
      expect(call.duration).toBeLessThan(5000); // 5 second max response time
    }
    
    // At least some API calls should have been made
    expect(apiCalls.length).toBeGreaterThan(0);
  });

  test('Concurrent user simulation', async () => {
    // Simulate multiple concurrent operations
    const operations = [
      // Operation 1: Load dashboard
      page.goto('/app/dashboard').then(() => 
        page.waitForSelector('[data-testid="dashboard-content"]')
      ),
      
      // Operation 2: Search inventory in new context
      page.context().newPage().then(async (newPage) => {
        await newPage.goto('/app/inventory');
        await newPage.waitForSelector('[data-testid="inventory-grid"]');
        await newPage.fill('[data-testid="search-input"]', 'test');
        await newPage.click('[data-testid="search-button"]');
        return newPage.close();
      }),
      
      // Operation 3: Load analytics
      page.context().newPage().then(async (newPage) => {
        await newPage.goto('/app/dashboard/analytics');
        await newPage.waitForSelector('[data-testid="analytics-content"]');
        return newPage.close();
      })
    ];
    
    const startTime = Date.now();
    
    // Execute all operations concurrently
    await Promise.all(operations);
    
    const totalTime = Date.now() - startTime;
    
    // Concurrent operations should complete in reasonable time
    expect(totalTime).toBeLessThan(10000);
  });

  test('Image and asset loading performance', async () => {
    await page.goto('/app/dashboard');
    
    // Monitor resource loading
    const resources: Array<{ url: string, type: string, size: number, duration: number }> = [];
    
    page.on('response', async (response) => {
      const request = response.request();
      const resourceType = request.resourceType();
      
      if (['image', 'stylesheet', 'script'].includes(resourceType)) {
        const timing = request.timing();
        const size = parseInt(response.headers()['content-length'] || '0', 10);
        
        resources.push({
          url: response.url(),
          type: resourceType,
          size: size,
          duration: timing.responseEnd - timing.responseStart
        });
      }
    });
    
    // Navigate to pages with assets
    await page.goto('/app/inventory');
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    await page.goto('/app/dashboard/analytics');
    await page.waitForSelector('[data-testid="analytics-content"]');
    
    // Wait for all resources to load
    await page.waitForTimeout(3000);
    
    // Verify asset loading performance
    for (const resource of resources) {
      // Images should load quickly
      if (resource.type === 'image') {
        expect(resource.duration).toBeLessThan(3000);
      }
      
      // Scripts and stylesheets should be reasonably sized
      if (['script', 'stylesheet'].includes(resource.type)) {
        expect(resource.size).toBeLessThan(1024 * 1024); // Less than 1MB
      }
    }
  });

  test('Form submission performance', async () => {
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    // Fill form
    await page.fill('[data-testid="product-name"]', 'Performance Test Product');
    await page.fill('[data-testid="product-sku"]', 'PERF-001');
    await page.fill('[data-testid="product-price"]', '99.99');
    await page.fill('[data-testid="product-quantity"]', '10');
    
    const submitStart = Date.now();
    
    // Submit form
    await page.click('[data-testid="save-product"]');
    
    // Wait for success confirmation
    await page.waitForSelector('[data-testid="success-message"]');
    
    const submitTime = Date.now() - submitStart;
    
    // Form submission should be fast
    expect(submitTime).toBeLessThan(3000);
  });

  test('Search and filter performance', async () => {
    await page.goto('/app/inventory');
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    // Test search performance
    const searchStart = Date.now();
    
    await page.fill('[data-testid="search-input"]', 'test product');
    await page.click('[data-testid="search-button"]');
    
    // Wait for search results
    await page.waitForSelector('[data-testid="search-results"]');
    
    const searchTime = Date.now() - searchStart;
    expect(searchTime).toBeLessThan(2000);
    
    // Test filter performance
    const filterStart = Date.now();
    
    await page.selectOption('[data-testid="category-filter"]', 'electronics');
    await page.waitForSelector('[data-testid="filtered-results"]');
    
    const filterTime = Date.now() - filterStart;
    expect(filterTime).toBeLessThan(1500);
  });

  test('Real-time updates performance', async () => {
    await page.goto('/app/dashboard');
    await page.waitForSelector('[data-testid="dashboard-content"]');
    
    // Monitor WebSocket or polling performance
    const updateTimes: number[] = [];
    
    page.on('response', (response) => {
      if (response.url().includes('/api/realtime') || response.url().includes('dashboard-data')) {
        updateTimes.push(Date.now());
      }
    });
    
    // Wait for real-time updates
    await page.waitForTimeout(10000);
    
    // Verify update frequency and performance
    if (updateTimes.length > 1) {
      const intervals: number[] = [];
      for (let i = 1; i < updateTimes.length; i++) {
        intervals.push(updateTimes[i] - updateTimes[i - 1]);
      }
      
      // Updates should be consistent (not too frequent, not too slow)
      const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
      expect(avgInterval).toBeGreaterThan(1000); // At least 1 second between updates
      expect(avgInterval).toBeLessThan(60000); // No longer than 1 minute between updates
    }
  });
});
