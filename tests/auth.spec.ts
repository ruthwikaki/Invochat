
import { test, expect } from '@playwright/test';

test.describe('Authentication and Authorization', () => {
  
  test('should allow a user to view the login page', async ({ page }) => {
    // Navigate to the login page
    await page.goto('/login');

    // The page should have a specific title
    await expect(page).toHaveTitle(/InvoChat/);

    // The login form should be visible
    const heading = page.getByRole('heading', { name: 'Welcome to Intelligent Inventory' });
    await expect(heading).toBeVisible();

    // Check for essential form fields and buttons
    await expect(page.getByLabel('Email')).toBeVisible();
    await expect(page.getByLabel('Password')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sign In' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Sign up' })).toBeVisible();
  });

  test('should redirect unauthenticated users from dashboard to login', async ({ page }) => {
    // Attempt to navigate to a protected route
    await page.goto('/dashboard');
    
    // Check that the URL has been changed to the login page
    await expect(page).toHaveURL('/login');
    
    // Verify that the login form is visible as a confirmation
    const heading = page.getByRole('heading', { name: 'Welcome to Intelligent Inventory' });
    await expect(heading).toBeVisible();
  });

  // You can add more tests here based on your checklist, for example:
  // test('should show an error for invalid login credentials', async ({ page }) => { ... });
  // test('should allow a new user to sign up', async ({ page }) => { ... });

});
