import { test, expect } from '@playwright/test';

test.describe('Authentication Security', () => {

  test('should have CSRF protection on login form', async ({ page }) => {
    await page.goto('/login');
    // Attempt to submit form without CSRF token by removing it from the DOM
    await page.evaluate(() => {
        const csrfInput = document.querySelector('input[name="csrf_token"]');
        if (csrfInput) {
            csrfInput.remove();
        }
    });

    await page.fill('input[name="email"]', 'test@example.com');
    await page.fill('input[name="password"]', 'password');
    await page.click('button[type="submit"]');

    // The server action should reject the request. We expect a redirect back to login with an error.
    await page.waitForURL(/.*login\?error=.*/);
    const errorMessage = page.locator('[role="alert"]');
    await expect(errorMessage).toContainText('Invalid form submission');
  });

  test('should have secure headers on application pages', async ({ page }) => {
    await page.goto('/dashboard');
    const headers = await page.evaluate(() => fetch(window.location.href).then(res => {
        const h: Record<string, string> = {};
        res.headers.forEach((value, key) => { h[key] = value; });
        return h;
    }));

    expect(headers['x-frame-options']).toBe('SAMEORIGIN');
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect(headers['content-security-policy']).toContain("default-src 'self'");
  });
});
