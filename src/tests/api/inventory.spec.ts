import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Inventory API', () => {

  test('GET /api/inventory should return inventory items', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.get('/api/inventory?page=1&limit=10');
    
    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data).toHaveProperty('items');
    expect(data).toHaveProperty('totalCount');
    expect(Array.isArray(data.items)).toBe(true);
  });
  


});
