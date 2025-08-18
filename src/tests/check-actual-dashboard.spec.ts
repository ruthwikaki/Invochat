// src/tests/check-actual-dashboard.spec.ts
import { test, expect } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

// Use shared authentication setup
test.use({ storageState: 'playwright/.auth/user.json' });

const testUser = credentials.test_users[0];

test('check dashboard data fetching', async ({ page }) => {
  // Enable console logging
  page.on('console', msg => {
    if (msg.type() === 'error') {
      console.log('Console error:', msg.text());
    }
  });
  
  // Monitor network requests
  page.on('response', response => {
    if (response.url().includes('/api/') || response.url().includes('supabase')) {
      console.log(`API call: ${response.status()} ${response.url()}`);
    }
  });
  
  // Skip login since we're using shared authentication
  // Navigate directly to dashboard
  await page.goto('/dashboard');
  await page.waitForURL('/dashboard', { timeout: 30000 });
  console.log('On dashboard page');
  
  // Wait longer for content to potentially load
  await page.waitForTimeout(10000);
  
  // Check what's actually on the page
  const hasEmptyState = await page.locator('text="Welcome to ARVO!"').count() > 0;
  const hasTotalRevenue = await page.locator('text="Total Revenue"').count() > 0;
  const hasTotalOrders = await page.locator('text="Total Orders"').count() > 0;
  
  console.log('Page state:');
  console.log('- Has empty state:', hasEmptyState);
  console.log('- Has Total Revenue:', hasTotalRevenue);
  console.log('- Has Total Orders:', hasTotalOrders);
  
  if (hasEmptyState) {
    // The dashboard thinks there's no data
    // Let's check if it's a client-side issue
    const pageContent = await page.content();
    if (pageContent.includes('initialMetrics')) {
      const metricsMatch = pageContent.match(/initialMetrics[":]+({[^}]+})/);
      if (metricsMatch) {
        console.log('Initial metrics in page:', metricsMatch[1]);
      }
    }
  }
  
  // Take a screenshot
  await page.screenshot({ path: 'dashboard-final-state.png', fullPage: true });
  
  // Try to manually check if auth is working
  const cookies = await page.context().cookies();
  const supabaseCookies = cookies.filter(c => c.name.includes('supabase'));
  console.log('Supabase cookies:', supabaseCookies.length);
  
  if (!hasEmptyState && hasTotalRevenue) {
    console.log('✅ Dashboard loaded successfully with data!');
  } else {
    throw new Error('Dashboard still showing empty state');
  }
});