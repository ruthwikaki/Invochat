import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Analytics API', () => {
  
  test('should get dashboard analytics data', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.get('/api/analytics/dashboard?range=30d');
    console.log('STATUS', response.status(), 'BODY', await response.text());
    
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data).toHaveProperty('total_revenue');
    expect(data).toHaveProperty('top_products');
  });


});
