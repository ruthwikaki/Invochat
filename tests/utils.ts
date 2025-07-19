
import type { Page, BrowserContext } from '@playwright/test';

/**
 * A utility function to log in a user for tests.
 * This should be called within a test.beforeEach block.
 * It assumes you have a user with these credentials in your test database.
 * @param page The Playwright Page object.
 * @param context The Playwright BrowserContext object.
 */
export async function login(page: Page, context: BrowserContext) {
  // Use a dummy user that should exist in your test environment
  const email = process.env.TEST_USER_EMAIL || 'test@example.com';
  const password = process.env.TEST_USER_PASSWORD || 'password123';
  
  // Go to the login page
  await page.goto('/login');

  // Fill in the credentials
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);

  // Click the sign-in button
  await page.getByRole('button', { name: 'Sign In' }).click();

  // Wait for navigation to the dashboard, confirming login was successful
  await page.waitForURL('/dashboard');

  // Save the authentication state to a file
  // This allows subsequent tests to reuse the logged-in state without
  // repeating the login process, making tests faster.
  await context.storageState({ path: 'storageState.json' });
}
