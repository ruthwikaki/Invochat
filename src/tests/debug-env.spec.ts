import { test, expect } from '@playwright/test';

test('debug environment', async ({ page }) => {
  // Enable console logging
  page.on('console', msg => console.log('Browser console:', msg.text()));
  page.on('pageerror', err => console.log('Page error:', err.message));
  
  // Add response logging
  page.on('response', response => {
    if (response.url().includes('/login') || response.url().includes('/dashboard')) {
      console.log(`Response: ${response.status()} ${response.url()}`);
    }
  });

  await page.goto('/login');
  console.log('At login page:', page.url());
  
  // Fill in the form
  await page.fill('input[name="email"]', 'testowner1@example.com');
  await page.fill('input[name="password"]', 'TestPass123!');
  
  // Take a screenshot before clicking
  await page.screenshot({ path: 'before-click.png' });
  
  // Click and wait for either navigation or error
  const submitButton = page.getByRole('button', { name: 'Sign In' });
  
  // Start waiting for navigation before clicking
  const navigationPromise = page.waitForURL('/dashboard', { 
    timeout: 30000 
  }).catch(e => {
    console.log('Navigation to dashboard failed:', e.message);
    return null;
  });
  
  await submitButton.click();
  console.log('Clicked submit button');
  
  // Wait a bit to see what happens
  await page.waitForTimeout(5000);
  
  // Check current URL
  console.log('Current URL after 5 seconds:', page.url());
  
  // Take a screenshot after waiting
  await page.screenshot({ path: 'after-wait.png' });
  
  // Check for any error messages
  const alerts = await page.locator('[role="alert"]').count();
  if (alerts > 0) {
    const alertTexts = await page.locator('[role="alert"]').allTextContents();
    console.log('Alerts found:', alertTexts);
  }
  
  // Check cookies
  const cookies = await page.context().cookies();
  const authCookies = cookies.filter(c => c.name.includes('auth') || c.name.includes('supabase'));
  console.log('Auth-related cookies:', authCookies.map(c => ({ name: c.name, value: c.value ? 'set' : 'not-set' })));
  
  // Wait for navigation result
  const navResult = await navigationPromise;
  if (navResult === null) {
    console.log('Failed to navigate to dashboard');
  } else {
    console.log('Successfully navigated to dashboard');
  }
});
