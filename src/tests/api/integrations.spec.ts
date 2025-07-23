import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Integrations API', () => {

  test('POST /api/shopify/connect should fail with invalid credentials', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.post('/api/shopify/connect', {
      data: {
        storeUrl: 'https://invalid-store.myshopify.com',
        accessToken: 'shpat_invalidtoken',
      }
    });
    
    expect(response.status()).toBe(500);
    const { error } = await response.json();
    expect(error).toContain('Authentication failed');
  });

  test('POST /api/shopify/sync requires authentication', async ({ request }) => {
    const response = await request.post('/api/shopify/sync', {
        data: { integrationId: 'some-uuid' }
    });
    expect(response.status()).toBe(401);
  });

});
