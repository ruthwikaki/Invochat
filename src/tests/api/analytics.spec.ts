import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Analytics API', () => {
  
  test('should get dashboard analytics data', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.get('/api/analytics/dashboard?range=30d');
    
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data).toHaveProperty('total_revenue');
    expect(data).toHaveProperty('top_products');
  });

  test('should reject unauthorized access to dashboard analytics', async ({ request }) => {
    const response = await request.get('/api/analytics/dashboard?range=30d');
    expect(response.status()).toBe(401);
  });
});
