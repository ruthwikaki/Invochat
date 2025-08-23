import { test, expect, Page } from '@playwright/test';

/**
 * End-to-End Business Workflow Tests
 * Critical business operations testing
 */

test.describe('Business Workflows', () => {
  let page: Page;

  test.beforeEach(async ({ page: testPage }) => {
    page = testPage;
    // Navigate to application
    await page.goto('/');
    
    // Mock authentication
    await page.addInitScript(() => {
      localStorage.setItem('supabase.auth.token', JSON.stringify({
        access_token: 'mock-token',
        user: { id: 'test-user', email: 'test@example.com' }
      }));
    });
  });

  test('Complete inventory management workflow', async () => {
    // Navigate to inventory
    await page.goto('/app/inventory');
    
    // Wait for inventory to load
    await page.waitForSelector('[data-testid="inventory-grid"]');
    
    // Add new product
    await page.click('[data-testid="add-product-button"]');
    await page.fill('[data-testid="product-name"]', 'Test Product');
    await page.fill('[data-testid="product-sku"]', 'TEST-001');
    await page.fill('[data-testid="product-price"]', '29.99');
    await page.fill('[data-testid="product-quantity"]', '100');
    await page.click('[data-testid="save-product"]');
    
    // Verify product was added
    await expect(page.locator('text=Test Product')).toBeVisible();
    
    // Edit product
    await page.click('[data-testid="edit-product-TEST-001"]');
    await page.fill('[data-testid="product-quantity"]', '150');
    await page.click('[data-testid="save-product"]');
    
    // Verify quantity updated
    await expect(page.locator('text=150')).toBeVisible();
  });

  test('Purchase order creation workflow', async () => {
    // Navigate to purchase orders
    await page.goto('/app/purchase-orders');
    
    // Create new PO
    await page.click('[data-testid="new-po-button"]');
    
    // Fill PO details
    await page.selectOption('[data-testid="supplier-select"]', 'supplier-1');
    await page.fill('[data-testid="po-notes"]', 'Test purchase order');
    
    // Add line items
    await page.click('[data-testid="add-line-item"]');
    await page.selectOption('[data-testid="product-select-0"]', 'TEST-001');
    await page.fill('[data-testid="quantity-0"]', '50');
    await page.fill('[data-testid="unit-cost-0"]', '15.00');
    
    // Submit PO
    await page.click('[data-testid="submit-po"]');
    
    // Verify PO created
    await expect(page.locator('[data-testid="po-success-message"]')).toBeVisible();
    await expect(page.locator('text=Test purchase order')).toBeVisible();
  });

  test('Analytics dashboard workflow', async () => {
    // Navigate to analytics
    await page.goto('/app/dashboard/analytics');
    
    // Wait for charts to load
    await page.waitForSelector('[data-testid="revenue-chart"]');
    await page.waitForSelector('[data-testid="inventory-metrics"]');
    
    // Verify key metrics are displayed
    await expect(page.locator('[data-testid="total-revenue"]')).toBeVisible();
    await expect(page.locator('[data-testid="inventory-value"]')).toBeVisible();
    await expect(page.locator('[data-testid="low-stock-alerts"]')).toBeVisible();
    
    // Test date range filtering
    await page.click('[data-testid="date-range-filter"]');
    await page.click('[data-testid="last-30-days"]');
    
    // Verify charts updated
    await page.waitForSelector('[data-testid="revenue-chart"]:not([data-loading="true"])');
    
    // Test export functionality
    await page.click('[data-testid="export-report"]');
    await expect(page.locator('[data-testid="export-success"]')).toBeVisible();
  });

  test('AI chat interaction workflow', async () => {
    // Navigate to AI chat
    await page.goto('/app/dashboard/chat');
    
    // Wait for chat interface
    await page.waitForSelector('[data-testid="chat-interface"]');
    
    // Send message to AI
    await page.fill('[data-testid="chat-input"]', 'What products should I reorder?');
    await page.click('[data-testid="send-message"]');
    
    // Wait for AI response
    await page.waitForSelector('[data-testid="ai-response"]');
    
    // Verify response contains reorder suggestions
    const response = await page.textContent('[data-testid="ai-response"]');
    expect(response).toContain('reorder');
    
    // Test follow-up question
    await page.fill('[data-testid="chat-input"]', 'Show me dead stock analysis');
    await page.click('[data-testid="send-message"]');
    
    // Verify second response
    await page.waitForSelector('[data-testid="ai-response"]:nth-child(4)');
  });

  test('Supplier management workflow', async () => {
    // Navigate to suppliers
    await page.goto('/app/suppliers');
    
    // Add new supplier
    await page.click('[data-testid="add-supplier"]');
    await page.fill('[data-testid="supplier-name"]', 'Test Supplier Inc');
    await page.fill('[data-testid="supplier-email"]', 'supplier@test.com');
    await page.fill('[data-testid="supplier-phone"]', '555-0123');
    await page.click('[data-testid="save-supplier"]');
    
    // Verify supplier added
    await expect(page.locator('text=Test Supplier Inc')).toBeVisible();
    
    // View supplier performance
    await page.click('[data-testid="view-supplier-performance"]');
    
    // Verify performance metrics displayed
    await expect(page.locator('[data-testid="supplier-score"]')).toBeVisible();
    await expect(page.locator('[data-testid="delivery-performance"]')).toBeVisible();
  });

  test('Integration sync workflow', async () => {
    // Navigate to integrations
    await page.goto('/app/integrations');
    
    // Test Shopify integration
    await page.click('[data-testid="shopify-sync"]');
    
    // Verify sync started
    await expect(page.locator('[data-testid="sync-in-progress"]')).toBeVisible();
    
    // Wait for sync completion (mock)
    await page.waitForTimeout(2000);
    await expect(page.locator('[data-testid="sync-completed"]')).toBeVisible();
    
    // Verify sync results
    await expect(page.locator('[data-testid="products-synced"]')).toBeVisible();
    await expect(page.locator('[data-testid="orders-synced"]')).toBeVisible();
  });

  test('Sales order processing workflow', async () => {
    // Navigate to sales orders
    await page.goto('/app/sales');
    
    // Create new sales order
    await page.click('[data-testid="new-order"]');
    
    // Fill customer information
    await page.fill('[data-testid="customer-email"]', 'customer@test.com');
    await page.fill('[data-testid="customer-name"]', 'Test Customer');
    
    // Add order items
    await page.click('[data-testid="add-order-item"]');
    await page.selectOption('[data-testid="product-select"]', 'TEST-001');
    await page.fill('[data-testid="order-quantity"]', '2');
    
    // Calculate total
    await page.click('[data-testid="calculate-total"]');
    await expect(page.locator('[data-testid="order-total"]')).toContainText('59.98');
    
    // Process order
    await page.click('[data-testid="process-order"]');
    
    // Verify order processed
    await expect(page.locator('[data-testid="order-confirmation"]')).toBeVisible();
  });

  test('Advanced analytics workflow', async () => {
    // Navigate to advanced analytics
    await page.goto('/app/dashboard/advanced-analytics');
    
    // Test ABC analysis
    await page.click('[data-testid="abc-analysis-tab"]');
    await page.waitForSelector('[data-testid="abc-chart"]');
    
    // Verify ABC categories
    await expect(page.locator('[data-testid="category-a-products"]')).toBeVisible();
    await expect(page.locator('[data-testid="category-b-products"]')).toBeVisible();
    await expect(page.locator('[data-testid="category-c-products"]')).toBeVisible();
    
    // Test demand forecasting
    await page.click('[data-testid="demand-forecast-tab"]');
    await page.waitForSelector('[data-testid="forecast-chart"]');
    
    // Verify forecast data
    await expect(page.locator('[data-testid="forecast-accuracy"]')).toBeVisible();
    await expect(page.locator('[data-testid="demand-trend"]')).toBeVisible();
  });
});
