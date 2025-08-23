import { test, expect, Page } from '@playwright/test';

/**
 * Security and Authentication Tests
 * Critical security validation testing
 */

test.describe('Security & Authentication', () => {
  let page: Page;

  test.beforeEach(async ({ page: testPage }) => {
    page = testPage;
  });

  test('Authentication flow security', async () => {
    // Test login page loads
    await page.goto('/auth/login');
    await expect(page.locator('[data-testid="login-form"]')).toBeVisible();
    
    // Test invalid credentials
    await page.fill('[data-testid="email-input"]', 'invalid@test.com');
    await page.fill('[data-testid="password-input"]', 'wrongpassword');
    await page.click('[data-testid="login-button"]');
    
    // Verify error message
    await expect(page.locator('[data-testid="error-message"]')).toBeVisible();
    
    // Test valid credentials
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Verify redirect to dashboard
    await expect(page).toHaveURL(/.*dashboard/);
  });

  test('Protected route access control', async () => {
    // Attempt to access protected route without auth
    await page.goto('/app/dashboard');
    
    // Should redirect to login
    await expect(page).toHaveURL(/.*login/);
    
    // Login first
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Now should access dashboard
    await expect(page).toHaveURL(/.*dashboard/);
  });

  test('CSRF protection validation', async () => {
    // Login first
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Navigate to form that should have CSRF protection
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    // Check for CSRF token in form
    const csrfToken = await page.getAttribute('[name="csrf-token"]', 'value');
    expect(csrfToken).toBeTruthy();
    expect(csrfToken).toHaveLength(40); // Standard CSRF token length
  });

  test('Session management and timeout', async () => {
    // Login
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Access dashboard
    await page.goto('/app/dashboard');
    await expect(page.locator('[data-testid="dashboard-content"]')).toBeVisible();
    
    // Simulate session expiry by clearing storage
    await page.evaluate(() => {
      localStorage.clear();
      sessionStorage.clear();
    });
    
    // Refresh page
    await page.reload();
    
    // Should redirect to login
    await expect(page).toHaveURL(/.*login/);
  });

  test('Password security requirements', async () => {
    // Go to signup page
    await page.goto('/auth/signup');
    
    // Test weak password
    await page.fill('[data-testid="email-input"]', 'newuser@test.com');
    await page.fill('[data-testid="password-input"]', '123');
    await page.click('[data-testid="signup-button"]');
    
    // Should show password strength error
    await expect(page.locator('[data-testid="password-error"]')).toBeVisible();
    
    // Test strong password
    await page.fill('[data-testid="password-input"]', 'StrongPass123!');
    await page.click('[data-testid="signup-button"]');
    
    // Should proceed or show success
    await expect(page.locator('[data-testid="password-error"]')).not.toBeVisible();
  });

  test('SQL injection prevention', async () => {
    // Login first
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Navigate to search functionality
    await page.goto('/app/inventory');
    
    // Attempt SQL injection in search
    const maliciousInput = "'; DROP TABLE products; --";
    await page.fill('[data-testid="search-input"]', maliciousInput);
    await page.click('[data-testid="search-button"]');
    
    // Should not break the application
    await expect(page.locator('[data-testid="inventory-grid"]')).toBeVisible();
    
    // Verify no SQL error messages
    const pageContent = await page.textContent('body');
    expect(pageContent).not.toContain('SQL');
    expect(pageContent).not.toContain('DROP TABLE');
  });

  test('XSS protection validation', async () => {
    // Login first
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Navigate to form input
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    // Attempt XSS injection
    const maliciousScript = '<script>alert("XSS")</script>';
    await page.fill('[data-testid="product-name"]', maliciousScript);
    await page.fill('[data-testid="product-sku"]', 'XSS-TEST');
    await page.click('[data-testid="save-product"]');
    
    // Verify script is not executed
    // Page should not show alert dialog
    await page.waitForTimeout(1000);
    
    // Verify content is properly escaped
    const productName = await page.textContent('[data-testid="product-name-display"]');
    expect(productName).toContain('&lt;script&gt;');
  });

  test('Content Security Policy compliance', async () => {
    // Navigate to application
    await page.goto('/');
    
    // Check CSP headers
    const response = await page.request.get('/');
    const cspHeader = response.headers()['content-security-policy'];
    
    expect(cspHeader).toBeTruthy();
    expect(cspHeader).toContain("default-src 'self'");
    expect(cspHeader).toContain("script-src 'self'");
    expect(cspHeader).toContain("style-src 'self'");
  });

  test('Rate limiting protection', async () => {
    // Test login rate limiting
    await page.goto('/auth/login');
    
    // Attempt multiple rapid login attempts
    for (let i = 0; i < 6; i++) {
      await page.fill('[data-testid="email-input"]', 'test@example.com');
      await page.fill('[data-testid="password-input"]', 'wrongpassword');
      await page.click('[data-testid="login-button"]');
      await page.waitForTimeout(100);
    }
    
    // Should show rate limit message
    await expect(page.locator('[data-testid="rate-limit-error"]')).toBeVisible();
  });

  test('Secure headers validation', async () => {
    const response = await page.request.get('/');
    const headers = response.headers();
    
    // Check security headers
    expect(headers['x-frame-options']).toBe('DENY');
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['x-xss-protection']).toBe('1; mode=block');
    expect(headers['strict-transport-security']).toContain('max-age=');
  });

  test('API endpoint authentication', async () => {
    // Test unauthenticated API access
    const response = await page.request.get('/api/analytics/dashboard');
    expect(response.status()).toBe(401);
    
    // Login and get token
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Get auth token from storage
    const token = await page.evaluate(() => {
      return localStorage.getItem('supabase.auth.token');
    });
    
    // Test authenticated API access
    if (token) {
      const authResponse = await page.request.get('/api/analytics/dashboard', {
        headers: {
          'Authorization': `Bearer ${JSON.parse(token).access_token}`
        }
      });
      expect(authResponse.status()).toBe(200);
    }
  });

  test('Data sanitization and validation', async () => {
    // Login first
    await page.goto('/auth/login');
    await page.fill('[data-testid="email-input"]', 'test@example.com');
    await page.fill('[data-testid="password-input"]', 'testpassword123');
    await page.click('[data-testid="login-button"]');
    
    // Test form validation
    await page.goto('/app/inventory');
    await page.click('[data-testid="add-product-button"]');
    
    // Submit empty form
    await page.click('[data-testid="save-product"]');
    
    // Should show validation errors
    await expect(page.locator('[data-testid="name-required-error"]')).toBeVisible();
    await expect(page.locator('[data-testid="sku-required-error"]')).toBeVisible();
    
    // Test data type validation
    await page.fill('[data-testid="product-price"]', 'not-a-number');
    await page.click('[data-testid="save-product"]');
    
    // Should show numeric validation error
    await expect(page.locator('[data-testid="price-numeric-error"]')).toBeVisible();
  });
});
