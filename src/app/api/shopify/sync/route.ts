
'use server';

import { NextResponse } from 'next/server';
import { z } from 'zod';
import { runSync } from '@/features/integrations/services/sync-service';
import { logError, getErrorMessage } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import crypto from 'crypto';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logWebhookEvent } from '@/services/database';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
});

async function validateShopifyWebhook(request: Request): Promise<boolean> {
    const shopifyHmac = request.headers.get('x-shopify-hmac-sha256');
    const shopifyTimestamp = request.headers.get('x-shopify-request-timestamp');

    if (!shopifyHmac || !shopifyTimestamp) {
        return false;
    }

    const requestTime = parseInt(shopifyTimestamp, 10);
    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(now - requestTime) > config.integrations.webhookReplayWindowSeconds) {
        logError(new Error(`Shopify webhook timestamp is too old. Request time: ${requestTime}, Current time: ${now}`), { status: 408 });
        return false;
    }

    const shopifyWebhookSecret = process.env.SHOPIFY_WEBHOOK_SECRET;
    if (!shopifyWebhookSecret) {
        logError(new Error('SHOPIFY_WEBHOOK_SECRET is not set. Cannot validate webhook.'));
        return false;
    }
    
    // We need to re-read the body here because it might have been consumed already
    const body = await request.text();
    // This is important: when creating the hash, it's against the raw body text.

    const hash = crypto
        .createHmac('sha256', shopifyWebhookSecret)
        .update(body)
        .digest('base64');
    
    try {
        return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(shopifyHmac));
    } catch (error) {
        // This catches potential errors if the hash or hmac are invalid lengths
        return false;
    }
}


export async function POST(request: Request) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'sync_endpoint', config.ratelimit.sync, 3600);
        if (limited) {
            return NextResponse.json({ error: 'Too many sync requests. Please try again in an hour.' }, { status: 429 });
        }

        const isWebhookTriggered = await validateShopifyWebhook(request.clone());

        // Now that we've potentially cloned and read the request body for webhook validation,
        // we can proceed to read it as JSON.
        const body = await request.json();

        // After reading body, we can handle webhook-specific logic
        if (isWebhookTriggered) {
             const webhookId = request.headers.get('x-shopify-webhook-id');
             const shopDomain = request.headers.get('x-shopify-shop-domain');
             if (webhookId && shopDomain) {
                const supabase = getServiceRoleClient();
                const { data: integration } = await supabase
                    .from('integrations')
                    .select('id')
                    .eq('shop_domain', `https://${shopDomain}`)
                    .single();

                if (integration) {
                    const { success } = await logWebhookEvent(integration.id, 'shopify', webhookId);
                    if (!success) {
                        logError(new Error(`Shopify webhook replay attempt detected: ${webhookId}`), { status: 409 });
                        return NextResponse.json({ error: 'Duplicate webhook event' }, { status: 409 });
                    }
                }
            }
        }
        
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
        if (!supabaseUrl || !supabaseAnonKey) {
            throw new Error("Supabase environment variables are not set for API route.");
        }

        const cookieStore = cookies();
        const authSupabase = createServerClient(
            supabaseUrl,
            supabaseAnonKey,
            {
              cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: { user } } = await authSupabase.auth.getUser();
        let companyId = user?.app_metadata?.company_id;

        const isUserTriggered = !!(user && companyId);
        
        if (!isUserTriggered && !isWebhookTriggered) {
             return NextResponse.json({ error: 'Authentication required: User or valid webhook signature not found.' }, { status: 401 });
        }
        
        const parsed = syncSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }

        const { integrationId } = parsed.data;

        if (isWebhookTriggered && !companyId) {
            const supabase = getServiceRoleClient();
             const { data: integration } = await supabase.from('integrations').select('company_id').eq('id', integrationId).single();
             if (!integration) {
                return NextResponse.json({ error: 'Integration not found for webhook.' }, { status: 404 });
             }
             companyId = integration.company_id;
        }

        if (!companyId) {
             return NextResponse.json({ error: 'Company could not be determined for sync operation.' }, { status: 400 });
        }

        runSync(integrationId, companyId).catch(err => {
             logError(err, { context: 'Background sync failed to start', integrationId });
        });

        return NextResponse.json({ success: true, message: "Sync started successfully. It will run in the background." });

    } catch (e: unknown) {
        logError(e, { context: 'Shopify Sync API' });
        const errorMessage = getErrorMessage(e);
        
        return NextResponse.json({ error: errorMessage }, { status: 500 });
    }
}
