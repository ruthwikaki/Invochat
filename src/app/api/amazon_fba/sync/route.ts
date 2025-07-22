
'use server';

import { NextResponse } from 'next/server';
import { z } from 'zod';
import { runSync } from '@/features/integrations/services/sync-service';
import { logError, getErrorMessage } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';

const syncSchema = z.object({
  integrationId: z.string().uuid(),
});

export async function POST(request: Request) {
    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'sync_endpoint', config.ratelimit.sync, 3600);
        if (limited) {
            return NextResponse.json({ error: 'Too many sync requests. Please try again in an hour.' }, { status: 429 });
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
        const companyId = user?.app_metadata?.company_id;

        if (!user || !companyId) {
            return NextResponse.json({ error: 'Authentication required: User or company not found.' }, { status: 401 });
        }
        
        const body = await request.json();
        const parsed = syncSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }

        const { integrationId } = parsed.data;
        
        // Asynchronously trigger the sync but don't await it here.
        // This allows the API to respond immediately.
        // The catch block handles any synchronous errors during initiation.
        runSync(integrationId, companyId).catch(err => {
             logError(err, { context: 'Background sync failed to start', integrationId });
        });

        return NextResponse.json({ success: true, message: "Sync started successfully. It will run in the background." });

    } catch (e: unknown) {
        logError(e, { context: 'Amazon FBA Sync API' });
        return NextResponse.json({ error: getErrorMessage(e) }, { status: 500 });
    }
}
