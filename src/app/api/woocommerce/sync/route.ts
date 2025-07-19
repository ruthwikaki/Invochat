
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
import { getErrorMessage } from '@/lib/error-handler';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
});

async function validateWooCommerceWebhook(request: Request): Promise<boolean> {
    const signature = request.headers.get('x-wc-webhook-signature');
    if (!signature) {
        return false;
    }
    
    const webhookSecret = process.env.WOOCOMMERCE_WEBHOOK_SECRET;
    if (!webhookSecret) {
        logError(new Error('WOOCOMMERCE_WEBHOOK_SECRET is not set. Cannot validate webhook.'));
        return false;
    }
    
    const body = await request.text();
    const hash = crypto.createHmac('sha256', webhookSecret).update(body).digest('base64');
    
    return hash === signature;
}


export async function POST(request: Request) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'sync_endpoint', config.ratelimit.sync, 3600);
        if (limited) {
            return NextResponse.json({ error: 'Too many sync requests. Please try again in an hour.' }, { status: 429 });
        }
        
        const isWebhookTriggered = await validateWooCommerceWebhook(request.clone());
        const body = await request.json();

        if (isWebhookTriggered) {
            const webhookId = request.headers.get('x-wc-webhook-id');
            const shopDomain = request.headers.get('x-wc-webhook-source');
            if (webhookId && shopDomain) {
                const supabase = getServiceRoleClient();
                const { data: integration } = await supabase
                    .from('integrations')
                    .select('id')
                    .eq('shop_domain', shopDomain)
                    .single();

                if (integration) {
                    const { success } = await logWebhookEvent(integration.id, 'woocommerce', webhookId);
                    if (!success) {
                        logError(new Error(`WooCommerce webhook replay attempt detected: ${webhookId}`), { status: 409 });
                        return NextResponse.json({ error: 'Duplicate webhook event' }, { status: 409 });
                    }
                }
            }
        }

        const cookieStore = cookies();
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

        if (!supabaseUrl || !supabaseAnonKey) {
            throw new Error("Supabase environment variables are not set.");
        }

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
        logError(e, { context: 'WooCommerce Sync API' });
        return NextResponse.json({ error: getErrorMessage(e) }, { status: 500 });
    }
}
