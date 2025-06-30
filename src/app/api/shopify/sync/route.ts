
'use server';

import { NextResponse } from 'next/server';
import { z } from 'zod';
import { runSync } from '@/features/integrations/services/sync-service';
import { logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
});

export async function POST(request: Request) {
    try {
        // --- Server-side Authentication ---
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

        if (!user || !companyId) {
            return NextResponse.json({ error: 'Authentication required: User or company not found.' }, { status: 401 });
        }
        // --- End Authentication ---
        
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
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
