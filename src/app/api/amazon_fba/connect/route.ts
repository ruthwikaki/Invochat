
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import type { Platform } from '@/features/integrations/types';
import { createOrUpdateSecret } from '@/features/integrations/services/encryption';
import { rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';

const connectSchema = z.object({
  sellerId: z.string().min(1, { message: 'Seller ID cannot be empty.' }),
  authToken: z.string().min(1, { message: 'MWS Auth Token cannot be empty.' }),
});

export async function POST(request: Request) {
    const platform: Platform = 'amazon_fba';

    try {
        const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
        const { limited } = await rateLimit(ip, 'connect', config.ratelimit.connect, 3600);
        if (limited) {
            return NextResponse.json({ error: 'Too many connection attempts. Please try again in an hour.' }, { status: 429 });
        }

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
        
        const body = await request.json();
        const parsed = connectSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }
        
        const { sellerId, authToken } = parsed.data;

        const credentialsToStore = JSON.stringify({ sellerId, authToken });
        // Securely store credentials in the vault
        await createOrUpdateSecret(companyId, platform, credentialsToStore);
        
        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('integrations')
            .upsert({
                company_id: companyId,
                platform: platform,
                shop_name: `Amazon Seller (${sellerId.slice(-4)})`,
                is_active: true,
                sync_status: 'idle',
            }, { onConflict: 'company_id, platform' })
            .select()
            .single();

        if (error) {
            logError(error, { context: 'Failed to save Amazon FBA integration' });
            throw new Error('Failed to save integration to the database.');
        }

        return NextResponse.json({ success: true, integration: data });

    } catch (e: any) {
        logError(e, { context: 'Amazon FBA Connect API' });
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
