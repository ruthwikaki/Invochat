import { test, expect } from '@playwright/test';

test.describe('Data Synchronization Service', () => {

    test('should handle a Shopify webhook sync trigger', async ({ request }) => {
        // This test simulates a webhook trigger from Shopify.
        // We need to construct a valid HMAC signature for the request.
        // In a real test suite, the secret would come from a test environment variable.
        const shopifyWebhookSecret = process.env.SHOPIFY_WEBHOOK_SECRET || 'test_secret';
        const crypto = require('crypto');
        
        const requestBody = JSON.stringify({ integrationId: 'a-fake-id-from-webhook' });
        
        const hmac = crypto
            .createHmac('sha256', shopifyWebhookSecret)
            .update(requestBody)
            .digest('base64');

        const response = await request.post('/api/shopify/sync', {
            headers: {
                'x-shopify-hmac-sha256': hmac,
                'x-shopify-request-timestamp': String(Math.floor(Date.now() / 1000)),
                'x-shopify-shop-domain': 'test-shop.myshopify.com',
            },
            data: requestBody
        });

        // Since the webhook is valid, but the integrationId doesn't exist, we expect an error
        // related to not finding the integration, which proves the webhook validation passed.
        // A 401 would mean the webhook validation failed.
        expect(response.status()).toBe(404); 
        const jsonResponse = await response.json();
        expect(jsonResponse.error).toContain('Integration not found');
    });

    test('should reject a Shopify webhook with an invalid signature', async ({ request }) => {
        const response = await request.post('/api/shopify/sync', {
            headers: {
                'x-shopify-hmac-sha256': 'invalid_signature',
                'x-shopify-request-timestamp': String(Math.floor(Date.now() / 1000)),
            },
            data: { integrationId: 'some-id' }
        });

        // Expect a 401 Unauthorized because the signature is bad.
        expect(response.status()).toBe(401);
    });
});
