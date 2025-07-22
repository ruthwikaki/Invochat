
import { test, expect } from '@playwright/test';

test.describe('Authentication and Authorization', () => {
  
  test.beforeEach(async ({ page }) => {
    // Navigate to the login page before each test
    await page.goto('/login');
  });

  test('should allow a user to view the login page', async ({ page }) => {
    // The page should have a specific title
    await expect(page).toHaveTitle(/InvoChat/);

    // The login form should be visible
    const heading = page.getByRole('heading', { name: 'Welcome Back' });
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
    await expect(page).toHaveURL(/login/);
    
    // Verify that the login form is visible as a confirmation
    const heading = page.getByRole('heading', { name: 'Welcome Back' });
    await expect(heading).toBeVisible();
  });

  test('should show an error for invalid login credentials', async ({ page }) => {
    // Fill in the form with invalid credentials
    await page.getByLabel('Email').fill('wrong@user.com');
    await page.getByLabel('Password').fill('wrongpassword');

    // Click the sign-in button
    await page.getByRole('button', { name: 'Sign In' }).click();

    // An error message should be displayed
    const errorMessage = page.getByRole('alert');
    await expect(errorMessage).toBeVisible();
    await expect(errorMessage).toContainText('Invalid login credentials');
  });
  
  test('should allow a new user to navigate to the signup page', async ({ page }) => {
    // Click the "Sign up" link
    await page.getByRole('link', { name: 'Sign up' }).click();

    // The URL should now be /signup
    await expect(page).toHaveURL(/signup/);

    // The signup form heading should be visible
    const heading = page.getByRole('heading', { name: 'Create Your Account' });
    await expect(heading).toBeVisible();
  });

  test('should show password mismatch error on signup', async ({ page }) => {
    await page.goto('/signup');

    await page.getByLabel('Company Name').fill('Test Co');
    await page.getByLabel('Email').fill(`test-user-${Date.now()}@example.com`);
    await page.getByLabel('Password').first().fill('password123');
    await page.getByLabel('Confirm Password').fill('password456');

    // Click the create account button
    await page.getByRole('button', { name: 'Create Account' }).click();

    // An error message should be displayed about passwords not matching
    const errorMessage = page.getByRole('alert');
    await expect(errorMessage).toBeVisible();
    await expect(errorMessage).toContainText('Passwords do not match');
  });

});
