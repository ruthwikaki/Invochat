import { test, expect } from '@playwright/test';
import * as crypto from 'crypto';

// This test simulates a webhook trigger from Shopify.
// It's a pure API test and does not require a browser or user login.

test.describe('Webhook Security', () => {
    const shopifyWebhookSecret = process.env.SHOPIFY_WEBHOOK_SECRET || 'test_secret_for_ci';

    test('should reject a Shopify webhook with a bad signature', async ({ request }) => {
        const response = await request.post('/api/shopify/sync', {
            headers: {
                'X-Shopify-Hmac-Sha256': 'invalid_signature',
                'X-Shopify-Shop-Domain': 'test.myshopify.com',
                'X-Shopify-Request-Timestamp': Math.floor(Date.now() / 1000).toString(),
            },
            data: { some: 'payload' },
        });

        expect(response.status()).toBe(401);
    });

    test('should reject a Shopify webhook with an old timestamp', async ({ request }) => {
        const requestBody = JSON.stringify({ integrationId: 'some-id' });
        const hmac = crypto
            .createHmac('sha256', shopifyWebhookSecret)
            .update(requestBody)
            .digest('base64');
        
        const oneHourAgo = Math.floor(Date.now() / 1000) - 3600;

        const response = await request.post('/api/shopify/sync', {
            headers: {
                'X-Shopify-Hmac-Sha256': hmac,
                'X-Shopify-Shop-Domain': 'test.myshopify.com',
                'X-Shopify-Request-Timestamp': oneHourAgo.toString(),
            },
            data: requestBody,
        });

        // The timestamp is too old, so the request should be rejected.
        // Even though the signature is valid, this prevents replay attacks.
        // It should result in a 401 Unauthorized or similar error. We check for non-200 status.
        expect(response.status()).not.toBe(200);
    });
});
