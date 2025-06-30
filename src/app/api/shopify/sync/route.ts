
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { decrypt } from '@/features/integrations/services/encryption';
import { runFullSync } from '@/features/integrations/services/shopify-sync';
import { logError } from '@/lib/error-handler';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
  companyId: z.string().uuid(),
});

export async function POST(request: Request) {
    try {
        const body = await request.json();
        const parsed = syncSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }

        const { integrationId, companyId } = parsed.data;
        const supabase = getServiceRoleClient();

        // Fetch integration details
        const { data: integration, error: fetchError } = await supabase
            .from('integrations')
            .select('*')
            .eq('id', integrationId)
            .eq('company_id', companyId)
            .single();

        if (fetchError || !integration) {
            throw new Error('Integration not found or access denied.');
        }

        // Decrypt the token
        const accessToken = decrypt(integration.access_token);
        
        // Set status to 'syncing'
        await supabase.from('integrations').update({ sync_status: 'syncing', last_sync_at: new Date().toISOString() }).eq('id', integrationId);

        // Intentionally not awaiting this to allow for a quick response to the client.
        // This process runs in the background. In a production app with very large stores,
        // this would be offloaded to a dedicated background worker/queue system (e.g., BullMQ, Inngest).
        runFullSync(integration, accessToken).catch(err => {
             logError(err, { context: 'Background Shopify sync failed' });
        });

        return NextResponse.json({ success: true, message: "Sync started successfully. It will run in the background." });

    } catch (e: any) {
        logError(e, { context: 'Shopify Sync API' });
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
