
import { NextResponse } from 'next/server';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { encrypt } from '@/features/integrations/services/encryption';
import { logError } from '@/lib/error-handler';

const connectSchema = z.object({
  storeUrl: z.string().url({ message: 'Please enter a valid store URL (e.g., https://your-store.myshopify.com).' }),
  accessToken: z.string().min(1, { message: 'Access token cannot be empty.' }),
});

// A helper to make authenticated requests to the Shopify Admin API
async function shopifyFetch(shopDomain: string, accessToken: string, endpoint: string) {
    const url = `${shopDomain}/admin/api/2023-10/${endpoint}`;
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
    try {
        const body = await request.json();
        const parsed = connectSchema.safeParse(body);

        if (!parsed.success) {
            return NextResponse.json({ error: parsed.error.flatten().fieldErrors }, { status: 400 });
        }
        
        const { storeUrl, accessToken } = parsed.data;

        // 1. Test the connection by fetching shop details
        const shopData = await shopifyFetch(storeUrl, accessToken, 'shop.json');
        
        if (!shopData?.shop?.name) {
            throw new Error('Could not verify Shopify credentials. Response was invalid.');
        }
        
        const shopName = shopData.shop.name;
        
        // 2. Encrypt the access token for secure storage
        const encryptedToken = encrypt(accessToken);

        // 3. Save the integration details to the database
        // This part needs the user's companyId. This should be passed from the client
        // or retrieved from the user's session if this were a protected route.
        // For now, we'll assume it's passed in the body for simplicity.
        // In a real app, you would get this from `getAuthContext()` from `data-actions`.
        const { companyId } = body; // Assume client sends this for now
        if (!companyId) {
             return NextResponse.json({ error: 'Company ID is missing.' }, { status: 400 });
        }

        const supabase = getServiceRoleClient();
        const { data, error } = await supabase
            .from('integrations')
            .upsert({
                company_id: companyId,
                platform: 'shopify',
                shop_domain: storeUrl,
                access_token: encryptedToken,
                shop_name: shopName,
                is_active: true,
                sync_status: 'idle',
            }, { onConflict: 'company_id, platform, shop_domain' })
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
