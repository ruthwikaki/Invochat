
'use server';

import { NextResponse } from 'next/server';
import { z } from 'zod';
import { runSync } from '@/features/integrations/services/sync-service';
import { logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import crypto from 'crypto';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logWebhookEvent } from '@/services/database';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
});

/**
 * Validates the signature of a WooCommerce webhook request.
 * @param request The incoming NextRequest.
 * @returns A promise that resolves to true if the signature is valid, false otherwise.
 */
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
        // --- Webhook Replay Protection ---
        const webhookId = request.headers.get('x-wc-webhook-id');
        const shopDomain = request.headers.get('x-wc-webhook-source'); // WooCommerce uses this header
        
        if (webhookId && shopDomain) {
            const supabase = getServiceRoleClient();
            const { data: integration } = await supabase
                .from('integrations')
                .select('id')
                .eq('shop_domain', shopDomain) // Find integration by its domain
                .single();

            if (integration) {
                const { success } = await logWebhookEvent(integration.id, 'woocommerce', webhookId);
                if (!success) {
                    logError(new Error(`WooCommerce webhook replay attempt detected: ${webhookId}`), { status: 409 });
                    return NextResponse.json({ error: 'Duplicate webhook event' }, { status: 409 });
                }
            }
        }
        // --- End Webhook Replay Protection ---


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

        const isUserTriggered = !!(user && companyId);
        const isWebhookTriggered = await validateWooCommerceWebhook(request.clone());

        if (!isUserTriggered && !isWebhookTriggered) {
             return NextResponse.json({ error: 'Authentication required: User or valid webhook signature not found.' }, { status: 401 });
        }
        
        const body = await request.json();
        const parsed = syncSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }

        const { integrationId } = parsed.data;
        
        runSync(integrationId, companyId).catch(err => {
             logError(err, { context: 'Background sync failed', integrationId });
        });

        return NextResponse.json({ success: true, message: "Sync started successfully. It will run in the background." });

    } catch (e: any) {
        logError(e, { context: 'WooCommerce Sync API' });
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
