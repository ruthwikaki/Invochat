import { test, expect, Page } from '@playwright/test';

/**
 * Database and Integration Validation Tests
 * Critical data integrity and system integration testing
 */

test.describe('Database & Integration Validation', () => {
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

  test('Database connection validation', async () => {
    // Navigate to a page that requires database access
    await page.goto('/app/dashboard');
    
    // Check for database health indicators
    await page.waitForSelector('[data-testid="dashboard-content"]');
    
    // Verify data is loading from database
    const metricsVisible = await page.isVisible('[data-testid="revenue-metric"]');
    expect(metricsVisible).toBeTruthy();
    
    // Check for any database error messages
    const errorMessages = await page.locator('[data-testid="db-error"]').count();
    expect(errorMessages).toBe(0);
  });

  test('Data consistency across operations', async () => {
    // Create a product
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    const testSku = `TEST-${Date.now()}`;
    await page.fill('[data-testid="product-name"]', 'Consistency Test Product');
    await page.fill('[data-testid="product-sku"]', testSku);
    await page.fill('[data-testid="product-price"]', '25.99');
    await page.fill('[data-testid="product-quantity"]', '50');
    await page.click('[data-testid="save-product"]');
    
    // Verify product appears in inventory list
    await page.waitForSelector(`[data-testid="product-${testSku}"]`);
    
    // Navigate to purchase orders and verify product is available
    await page.goto('/app/purchase-orders');
    await page.click('[data-testid="new-po-button"]');
    await page.selectOption('[data-testid="supplier-select"]', 'supplier-1');
    await page.click('[data-testid="add-line-item"]');
    
    // Product should be available in dropdown
    const productOption = await page.locator(`[data-testid="product-select-0"] option[value="${testSku}"]`);
    await expect(productOption).toBeVisible();
  });

  test('Transaction integrity', async () => {
    // Test that database transactions work correctly
    await page.goto('/app/sales');
    await page.click('[data-testid="new-order"]');
    
    // Create an order that should update inventory
    const testSku = 'TRANS-TEST-001';
    
    // Fill order details
    await page.fill('[data-testid="customer-email"]', 'trans-test@example.com');
    await page.fill('[data-testid="customer-name"]', 'Transaction Test');
    
    // Add order item
    await page.click('[data-testid="add-order-item"]');
    await page.selectOption('[data-testid="product-select"]', testSku);
    await page.fill('[data-testid="order-quantity"]', '5');
    
    // Get initial inventory count
    const initialInventory = await page.evaluate(async (sku) => {
      const response = await fetch(`/api/inventory/product/${sku}`);
      const data = await response.json();
      return data.quantity;
    }, testSku);
    
    // Process order
    await page.click('[data-testid="process-order"]');
    await page.waitForSelector('[data-testid="order-confirmation"]');
    
    // Verify inventory was decremented
    const finalInventory = await page.evaluate(async (sku) => {
      const response = await fetch(`/api/inventory/product/${sku}`);
      const data = await response.json();
      return data.quantity;
    }, testSku);
    
    expect(finalInventory).toBe(initialInventory - 5);
  });

  test('Foreign key constraints', async () => {
    // Test that foreign key relationships are enforced
    await page.goto('/app/suppliers');
    
    // Try to delete a supplier that has associated purchase orders
    const supplierWithOrders = await page.locator('[data-testid="supplier-with-orders"]').first();
    if (await supplierWithOrders.isVisible()) {
      await supplierWithOrders.click();
      await page.click('[data-testid="delete-supplier"]');
      
      // Should show error about existing purchase orders
      await expect(page.locator('[data-testid="foreign-key-error"]')).toBeVisible();
      await expect(page.locator('text=Cannot delete supplier with existing purchase orders')).toBeVisible();
    }
  });

  test('Database backup and recovery simulation', async () => {
    // Simulate creating important data
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    const backupTestSku = `BACKUP-${Date.now()}`;
    await page.fill('[data-testid="product-name"]', 'Backup Test Product');
    await page.fill('[data-testid="product-sku"]', backupTestSku);
    await page.fill('[data-testid="product-price"]', '99.99');
    await page.fill('[data-testid="product-quantity"]', '100');
    await page.click('[data-testid="save-product"]');
    
    // Verify product was created
    await page.waitForSelector(`[data-testid="product-${backupTestSku}"]`);
    
    // Simulate data recovery check by refreshing and verifying persistence
    await page.reload();
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    // Product should still exist after refresh
    await expect(page.locator(`[data-testid="product-${backupTestSku}"]`)).toBeVisible();
  });

  test('Multi-user concurrent access', async () => {
    // Simulate multiple users accessing the same data
    const context1 = await page.context();
    const context2 = await page.context().browser()?.newContext();
    
    if (context2) {
      const page2 = await context2.newPage();
      
      // Both users navigate to inventory
      await page.goto('/app/inventory');
      await page2.goto('/app/inventory');
      
      // User 1 creates a product
      await page.click('[data-testid="add-product-button"]');
      const concurrentTestSku = `CONCURRENT-${Date.now()}`;
      await page.fill('[data-testid="product-name"]', 'Concurrent Test');
      await page.fill('[data-testid="product-sku"]', concurrentTestSku);
      await page.fill('[data-testid="product-price"]', '15.99');
      await page.fill('[data-testid="product-quantity"]', '25');
      await page.click('[data-testid="save-product"]');
      
      // Wait a moment for the change to propagate
      await page.waitForTimeout(1000);
      
      // User 2 refreshes and should see the new product
      await page2.reload();
      await page2.waitForSelector('[data-testid="inventory-grid"]');
      
      // Product should be visible to both users
      await expect(page.locator(`[data-testid="product-${concurrentTestSku}"]`)).toBeVisible();
      await expect(page2.locator(`[data-testid="product-${concurrentTestSku}"]`)).toBeVisible();
      
      await context2.close();
    }
  });

  test('Data validation and constraints', async () => {
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    // Test duplicate SKU constraint
    await page.fill('[data-testid="product-name"]', 'Duplicate SKU Test');
    await page.fill('[data-testid="product-sku"]', 'EXISTING-SKU-001');
    await page.fill('[data-testid="product-price"]', '10.00');
    await page.fill('[data-testid="product-quantity"]', '1');
    await page.click('[data-testid="save-product"]');
    
    // Should show duplicate SKU error
    await expect(page.locator('[data-testid="duplicate-sku-error"]')).toBeVisible();
    
    // Test negative price constraint
    await page.fill('[data-testid="product-sku"]', 'NEGATIVE-PRICE-TEST');
    await page.fill('[data-testid="product-price"]', '-5.00');
    await page.click('[data-testid="save-product"]');
    
    // Should show negative price error
    await expect(page.locator('[data-testid="negative-price-error"]')).toBeVisible();
  });

  test('Integration API endpoints', async () => {
    // Test Shopify integration endpoint
    const shopifyResponse = await page.request.get('/api/shopify/connect', {
      headers: {
        'Authorization': 'Bearer mock-token'
      }
    });
    
    // Should return proper response structure
    expect([200, 400, 401]).toContain(shopifyResponse.status());
    
    // Test WooCommerce integration endpoint
    const wooResponse = await page.request.get('/api/woocommerce/connect', {
      headers: {
        'Authorization': 'Bearer mock-token'
      }
    });
    
    expect([200, 400, 401]).toContain(wooResponse.status());
    
    // Test Amazon FBA integration endpoint
    const amazonResponse = await page.request.get('/api/amazon_fba/connect', {
      headers: {
        'Authorization': 'Bearer mock-token'
      }
    });
    
    expect([200, 400, 401]).toContain(amazonResponse.status());
  });

  test('Real-time data synchronization', async () => {
    // Navigate to dashboard with real-time features
    await page.goto('/app/dashboard');
    await page.waitForSelector('[data-testid="dashboard-content"]');
    
    // Get initial metric values
    const initialRevenue = await page.textContent('[data-testid="total-revenue"]');
    const initialOrders = await page.textContent('[data-testid="total-orders"]');
    
    // Create a new sale to trigger real-time update
    await page.goto('/app/sales');
    await page.click('[data-testid="new-order"]');
    
    await page.fill('[data-testid="customer-email"]', 'realtime@test.com');
    await page.fill('[data-testid="customer-name"]', 'Realtime Test');
    
    await page.click('[data-testid="add-order-item"]');
    await page.selectOption('[data-testid="product-select"]', 'TEST-001');
    await page.fill('[data-testid="order-quantity"]', '1');
    
    await page.click('[data-testid="process-order"]');
    await page.waitForSelector('[data-testid="order-confirmation"]');
    
    // Navigate back to dashboard
    await page.goto('/app/dashboard');
    await page.waitForSelector('[data-testid="dashboard-content"]');
    
    // Wait for real-time update
    await page.waitForTimeout(3000);
    
    // Verify metrics have updated
    const updatedRevenue = await page.textContent('[data-testid="total-revenue"]');
    const updatedOrders = await page.textContent('[data-testid="total-orders"]');
    
    // At least one metric should have changed
    const metricsChanged = (initialRevenue !== updatedRevenue) || (initialOrders !== updatedOrders);
    expect(metricsChanged).toBeTruthy();
  });

  test('Data migration integrity', async () => {
    // Test import functionality to ensure data migration works
    await page.goto('/app/import');
    
    // Mock CSV file upload
    const csvContent = `name,sku,price,quantity
Migration Test 1,MIG-001,10.99,50
Migration Test 2,MIG-002,15.99,75`;
    
    // Create a file and upload it
    await page.setInputFiles('[data-testid="csv-upload"]', {
      name: 'migration-test.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from(csvContent)
    });
    
    // Process the import
    await page.click('[data-testid="process-import"]');
    await page.waitForSelector('[data-testid="import-success"]');
    
    // Verify products were imported correctly
    await page.goto('/app/inventory');
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    await expect(page.locator('text=Migration Test 1')).toBeVisible();
    await expect(page.locator('text=Migration Test 2')).toBeVisible();
    await expect(page.locator('text=MIG-001')).toBeVisible();
    await expect(page.locator('text=MIG-002')).toBeVisible();
  });

  test('Database performance under load', async () => {
    // Test multiple rapid database operations
    await page.goto('/app/inventory');
    
    const operations: Promise<number>[] = [];
    const startTime = Date.now();
    
    // Create multiple products rapidly
    for (let i = 0; i < 5; i++) {
      operations.push(
        page.evaluate(async (index) => {
          const response = await fetch('/api/inventory/products', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer mock-token'
            },
            body: JSON.stringify({
              name: `Load Test Product ${index}`,
              sku: `LOAD-${index}-${Date.now()}`,
              price: 10.99 + index,
              quantity: 10 + index
            })
          });
          return response.status;
        }, i)
      );
    }
    
    // Execute all operations concurrently
    const results = await Promise.all(operations);
    const totalTime = Date.now() - startTime;
    
    // All operations should succeed
    results.forEach(status => {
      expect([200, 201]).toContain(status);
    });
    
    // Should complete within reasonable time
    expect(totalTime).toBeLessThan(10000);
  });

  test('Database error handling', async () => {
    // Test handling of database errors
    await page.goto('/app/inventory');
    
    // Attempt to create product with invalid data to trigger database error
    const response = await page.evaluate(async () => {
      try {
        const response = await fetch('/api/inventory/products', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer mock-token'
          },
          body: JSON.stringify({
            name: '', // Empty name should trigger validation error
            sku: '', // Empty SKU should trigger validation error
            price: 'invalid', // Invalid price type
            quantity: -1 // Negative quantity
          })
        });
        return response.status;
      } catch (error) {
        return 'error';
      }
    });
    
    // Should return proper error status
    expect([400, 422]).toContain(response);
  });
});
