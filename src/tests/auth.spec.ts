
import { test, expect } from '@playwright/test';

test.describe('Authentication and Authorization', () => {

  test('should show validation error for bad login', async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="email"]', 'wrong@user.com');
    await page.fill('input[name="password"]', 'wrongpassword');
    await page.click('button[type="submit"]');

    const errorMessage = page.locator('[role="alert"]');
    await expect(errorMessage).toBeVisible();
    await expect(errorMessage).toContainText('Invalid login credentials');
  });

  test('should show validation errors for signup', async ({ page }) => {
    await page.goto('/signup');
    await page.fill('input[name="password"]', 'short');
    await page.fill('input[name="confirmPassword"]', 'different');
    await page.click('button[type="submit"]');
    
    // This tests browser validation, but we can also check for server errors
    const passwordInput = page.locator('input[name="password"]');
    const validity = await passwordInput.evaluate((input: HTMLInputElement) => input.validity.tooShort);
    expect(validity).toBe(true);
  });
  
  test('should redirect unauthenticated user from protected page', async ({ page }) => {
    await page.goto('/dashboard');
    // Expect to be redirected to the login page
    await expect(page).toHaveURL(/.*login/);
  });
});
