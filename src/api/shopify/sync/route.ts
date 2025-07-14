

'use server';

import { NextResponse } from 'next/server';
import { z } from 'zod';
import { runSync } from '@/features/integrations/services/sync-service';
import { logError } from '@/lib/error-handler';
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

/**
 * Validates the HMAC signature of a Shopify webhook request.
 * @param request The incoming NextRequest.
 * @returns A promise that resolves to true if the signature is valid, false otherwise.
 */
async function validateShopifyWebhook(request: Request): Promise<boolean> {
  const shopifyHmac = request.headers.get('x-shopify-hmac-sha256');
  if (!shopifyHmac) {
    return false; // No signature header present
  }

  const shopifyWebhookSecret = process.env.SHOPIFY_WEBHOOK_SECRET;
  if (!shopifyWebhookSecret) {
    logError(new Error('SHOPIFY_WEBHOOK_SECRET is not set. Cannot validate webhook.'));
    return false; // Cannot validate without the secret
  }
  
  const body = await request.text();

  const hash = crypto
    .createHmac('sha256', shopifyWebhookSecret)
    .update(body)
    .digest('base64');
  
  // Use a timing-safe comparison to prevent timing attacks
  try {
    return crypto.timingSafeEqual(Buffer.from(hash), Buffer.from(shopifyHmac));
  } catch (error) {
    // This can happen if the buffers have different lengths
    return false;
  }
}


export async function POST(request: Request) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'sync_endpoint', config.ratelimit.import, 3600); // Limit to 10 syncs per hour
        if (limited) {
            return NextResponse.json({ error: 'Too many sync requests. Please try again in an hour.' }, { status: 429 });
        }

        // --- Webhook Replay Protection ---
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
                const { success, error } = await logWebhookEvent(integration.id, 'shopify', webhookId);
                if (!success) {
                    // This means the webhook ID has been processed before.
                    logError(new Error(`Shopify webhook replay attempt detected: ${webhookId}`), { status: 409 });
                    return NextResponse.json({ error: 'Duplicate webhook event' }, { status: 409 });
                }
            }
        }
        // --- End Webhook Replay Protection ---


        // --- Server-side Authentication & Authorization ---
        const cookieStore = cookies();
        const authSupabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            {
              cookies: { get: (name: string) => cookieStore.get(name)?.value },
            }
        );
        const { data: { user } } = await authSupabase.auth.getUser();
        const companyId = user?.app_metadata?.company_id;

        // An action can be triggered by an authenticated user OR a valid webhook
        const isUserTriggered = !!(user && companyId);
        // The clone is needed because the body can only be read once.
        const isWebhookTriggered = await validateShopifyWebhook(request.clone());
        
        if (!isUserTriggered && !isWebhookTriggered) {
             return NextResponse.json({ error: 'Authentication required: User or valid webhook signature not found.' }, { status: 401 });
        }
        
        const body = await request.json();
        const parsed = syncSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }

        const { integrationId } = parsed.data;

        // Intentionally not awaiting this to allow for a quick response to the client.
        // This process runs in the background. In a production app with very large stores,
        // this would be offloaded to a dedicated background worker/queue system (e.g., BullMQ, Inngest).
        runSync(integrationId, companyId).catch(err => {
             logError(err, { context: 'Background sync failed', integrationId });
        });

        return NextResponse.json({ success: true, message: "Sync started successfully. It will run in the background." });

    } catch (e: any) {
        logError(e, { context: 'Shopify Sync API' });
        const errorMessage = e.message || "An unexpected error occurred.";
        
        return NextResponse.json({ error: errorMessage }, { status: 500 });
    }
}
