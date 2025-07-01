
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { createVaultSecret, updateVaultSecret } from '@/features/integrations/services/encryption';
import { logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { Platform } from '@/features/integrations/types';

const connectSchema = z.object({
  storeUrl: z.string().url({ message: 'Please enter a valid store URL (e.g., https://your-store.com).' }),
  consumerKey: z.string().startsWith('ck_', { message: 'Key must start with "ck_"' }),
  consumerSecret: z.string().startsWith('cs_', { message: 'Secret must start with "cs_"' }),
});

export async function POST(request: Request) {
    const platform: Platform = 'woocommerce';

    try {
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
        
        const { storeUrl, consumerKey, consumerSecret } = parsed.data;
        
        const credentialsToStore = JSON.stringify({ consumerKey, consumerSecret });
        const supabase = getServiceRoleClient();

        const { data: existingIntegration } = await supabase
            .from('integrations')
            .select('id, access_token')
            .eq('company_id', companyId)
            .eq('platform', platform)
            .single();

        let vaultSecretId: string;

        if (existingIntegration?.access_token) {
            vaultSecretId = existingIntegration.access_token;
            await updateVaultSecret(vaultSecretId, credentialsToStore);
        } else {
            vaultSecretId = await createVaultSecret(companyId, platform, credentialsToStore);
        }

        const { data, error } = await supabase
            .from('integrations')
            .upsert({
                company_id: companyId,
                platform: platform,
                shop_domain: storeUrl,
                access_token: vaultSecretId,
                shop_name: new URL(storeUrl).hostname,
                is_active: true,
                sync_status: 'idle',
            }, { onConflict: 'company_id, platform' })
            .select()
            .single();

        if (error) {
            logError(error, { context: 'Failed to save WooCommerce integration' });
            throw new Error('Failed to save integration to the database.');
        }

        return NextResponse.json({ success: true, integration: data });

    } catch (e: any) {
        logError(e, { context: 'WooCommerce Connect API' });
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
