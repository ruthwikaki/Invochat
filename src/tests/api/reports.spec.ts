import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Reports API', () => {

  test('GET /api/reports/dead-stock should return a dead stock report', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.get('/api/reports/dead-stock');
    
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data).toHaveProperty('deadStockItems');
    expect(data).toHaveProperty('totalValue');
    expect(Array.isArray(data.deadStockItems)).toBe(true);
  });

});
