
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { createOrUpdateSecret } from '@/features/integrations/services/encryption';
import { logError } from '@/lib/error-handler';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { Platform } from '@/features/integrations/types';

const connectSchema = z.object({
  storeUrl: z.string().url({ message: 'Please enter a valid store URL (e.g., https://your-store.myshopify.com).' }),
  accessToken: z.string().min(1, { message: 'Access token cannot be empty.' }),
});

async function shopifyFetch(shopDomain: string, accessToken: string, endpoint: string) {
    const url = `https://${new URL(shopDomain).hostname}/admin/api/2024-04/${endpoint}`;
    const response = await fetch(url, {
        method: 'GET',
        headers: {
            'X-Shopify-Access-Token': accessToken,
            'Content-Type': 'application/json',
        },
    });

    if (!response.ok) {
        const errorBody = await response.text();
        throw new Error(`Shopify API error (${response.status}): ${errorBody}`);
    }
    return response.json();
}

export async function POST(request: Request) {
    const platform: Platform = 'shopify';

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
        
        const { storeUrl, accessToken } = parsed.data;

        const shopData = await shopifyFetch(storeUrl, accessToken, 'shop.json');
        
        if (!shopData?.shop?.name) {
            throw new Error('Could not verify Shopify credentials. Response was invalid.');
        }
        
        const shopName = shopData.shop.name;
        
        // Store the credentials securely in the Vault
        const credentialsToStore = JSON.stringify({ accessToken });
        await createOrUpdateSecret(companyId, platform, credentialsToStore);

        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('integrations')
            .upsert({
                company_id: companyId,
                platform: platform,
                shop_domain: storeUrl,
                shop_name: shopName,
                is_active: true,
                sync_status: 'idle',
            }, { onConflict: 'company_id, platform' })
            .select()
            .single();

        if (error) {
            logError(error, { context: 'Failed to save Shopify integration' });
            throw new Error('Failed to save integration to the database.');
        }

        return NextResponse.json({ success: true, integration: data });

    } catch (e: any) {
        logError(e, { context: 'Shopify Connect API' });
        const errorMessage = e.message.includes('401')
          ? "Authentication failed. Please check your Admin API access token and store URL."
          : e.message;
        return NextResponse.json({ error: errorMessage }, { status: 500 });
    }
}
