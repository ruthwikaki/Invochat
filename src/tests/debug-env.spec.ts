import { test, expect } from '@playwright/test';

test('debug environment', async ({ page }) => {
  // Go to a page that will trigger Next.js to load
  await page.goto('/');
  
  // Check if the page loads at all
  const response = await page.goto('/login');
  console.log('Login page status:', response?.status());
  
  // Try to check what's in the browser console
  page.on('console', msg => console.log('Browser console:', msg.text()));
  page.on('pageerror', err => console.log('Page error:', err.message));
  
  // Check if Supabase is initialized
  const supabaseCheck = await page.evaluate(() => {
    return {
      hasWindow: typeof window !== 'undefined',
      url: window.location.href,
      // Check if any Supabase-related errors in the page
      bodyText: document.body.innerText.substring(0, 500)
    };
  });
  
  console.log('Page check:', supabaseCheck);
  
  // Try the actual login
  await page.fill('input[name="email"]', 'testowner1@example.com');
  await page.fill('input[name="password"]', 'TestPass123!');
  
  // Take a screenshot before clicking
  await page.screenshot({ path: 'before-click.png' });
  
  await page.click('button[type="submit"]');
  
  // Wait a bit and take another screenshot
  await page.waitForTimeout(3000);
  await page.screenshot({ path: 'after-click.png' });
  
  console.log('Final URL:', page.url());
});
