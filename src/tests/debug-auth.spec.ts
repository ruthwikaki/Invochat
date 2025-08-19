// src/tests/debug-auth.spec.ts
import { test } from '@playwright/test';

test('debug auth and data access', async ({ page, request }) => {
  // Using shared authentication state - already logged in
  await page.goto('/dashboard', { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForURL('/dashboard');
  
  // Check what the API returns
  const apiResponse = await request.get('/api/analytics/dashboard');
  console.log('API Status:', apiResponse.status());
  
  if (apiResponse.ok()) {
    const data = await apiResponse.json();
    console.log('API Data:', JSON.stringify(data, null, 2));
  } else {
    console.log('API Error:', await apiResponse.text());
  }
  
  // Check page content
  const hasEmptyState = await page.locator('text="Welcome to ARVO!"').count() > 0;
  console.log('Has empty state:', hasEmptyState);
  
  // Try direct database query through API
  const testResponse = await request.get('/api/test-db');
  if (testResponse.ok()) {
    const testData = await testResponse.json();
    console.log('Direct DB test:', testData);
  }
});