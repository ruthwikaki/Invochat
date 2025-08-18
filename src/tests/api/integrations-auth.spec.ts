
import { test, expect } from '@playwright/test';

test.describe('Integrations API', () => {

  test('POST /api/shopify/connect should fail for an unauthenticated user', async ({ request }) => {
    const response = await request.post('/api/shopify/connect', {
      data: {
        storeUrl: 'https://invalid-store.myshopify.com',
        accessToken: 'shpat_invalidtoken',
      }
    });
    
    expect(response.status()).toBe(401); // Connect endpoint returns 401 for unauthenticated users
  });

  test('POST /api/shopify/sync requires authentication', async ({ request }) => {
    const response = await request.post('/api/shopify/sync', {
        data: { integrationId: '12345678-1234-1234-1234-123456789012' } // Valid UUID format
    });
    expect(response.status()).toBe(401); // Should check auth before processing request
  });

});
