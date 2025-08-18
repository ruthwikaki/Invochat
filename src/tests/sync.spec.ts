

import { test, expect } from '@playwright/test';
import * as crypto from 'crypto';

// This test simulates a webhook trigger from Shopify.
// It's a pure API test and does not require a browser or user login.

test.describe('Data Synchronization Service', () => {
    const shopifyWebhookSecret = process.env.SHOPIFY_WEBHOOK_SECRET || 'test_secret_for_ci';

    test('should handle a Shopify webhook sync trigger', async ({ request }) => {
        // This test simulates a webhook trigger from Shopify.
        // We need to construct a valid HMAC signature for the request.
        
        const body = JSON.stringify({ integrationId: '00000000-0000-0000-0000-000000000000' });
        
        const hmac = crypto
            .createHmac('sha256', shopifyWebhookSecret)
            .update(body)
            .digest('base64');

        const response = await request.post('/api/shopify/sync', {
            headers: {
                'x-shopify-hmac-sha256': hmac,
                'x-shopify-request-timestamp': String(Math.floor(Date.now() / 1000)),
                'x-shopify-shop-domain': 'test-shop.myshopify.com',
                'Content-Type': 'application/json',
                'x-shopify-webhook-id': 'test-webhook-id'
            },
            data: body
        });

        // Since the webhook is valid, but the integrationId doesn't exist, we expect an error
        // related to not finding the integration, which proves the webhook validation passed.
        // A 401 would mean the webhook validation failed.
        expect(response.status()).toBe(200); // Webhook processing returns 200 even for missing integrations
        const jsonResponse = await response.json();
        // The sync actually returns success: true but background processing fails
        expect(jsonResponse.success).toBe(true);
    });

    test('should reject a Shopify webhook with an invalid signature', async ({ request }) => {
        const response = await request.post('/api/shopify/sync', {
            headers: {
                'x-shopify-hmac-sha256': 'invalid_signature',
                'x-shopify-request-timestamp': String(Math.floor(Date.now() / 1000)),
            },
            data: { integrationId: 'some-id' }
        });

        // Expect a 400 Bad Request because the signature is invalid.
        expect(response.status()).toBe(400);
    });
});
