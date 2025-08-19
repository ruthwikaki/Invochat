// src/tests/debug-dashboard.spec.ts
import { test } from '@playwright/test';

test('debug dashboard loading', async ({ page }) => {
  console.log('Testing with shared authentication');
  
  // Using shared authentication state - already logged in
  await page.goto('/dashboard');
  await page.waitForURL('/dashboard');
  console.log('Reached dashboard');
  
  // Wait for content to load
  await page.waitForTimeout(5000);
  
  // Take screenshot
  await page.screenshot({ path: 'dashboard-debug.png', fullPage: true });
  
  // Check what's on the page
  const bodyText = await page.locator('body').innerText();
  console.log('Dashboard content:', bodyText.substring(0, 500));
  
  // Check for empty state
  const hasEmptyState = await page.locator('text="Welcome to ARVO!"').count();
  if (hasEmptyState > 0) {
    console.log('❌ Dashboard showing empty state!');
    
    // Check cookies for auth
    const cookies = await page.context().cookies();
    const authCookies = cookies.filter(c => c.name.includes('auth-token') || c.name.includes('supabase'));
    console.log('Auth cookies:', authCookies.map(c => c.name));
    
    // Try to check API directly
    const response = await page.request.get('/api/analytics/dashboard');
    console.log('API Response status:', response.status());
    if (!response.ok()) {
      console.log('API Error:', await response.text());
    } else {
      const data = await response.json();
      console.log('API Data:', JSON.stringify(data).substring(0, 200));
    }
  } else {
    console.log('✅ Dashboard loaded with data');
    
    // Check for specific elements
    const elements = [
      'Total Revenue',
      'Total Orders',
      'New Customers',
      'Sales Overview'
    ];
    
    for (const element of elements) {
      const count = await page.locator(`text="${element}"`).count();
      console.log(`"${element}": ${count > 0 ? '✅ Found' : '❌ Not found'}`);
    }
  }
});