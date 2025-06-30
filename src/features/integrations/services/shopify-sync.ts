
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { ShopifyIntegration } from '../types';

const SHOPIFY_API_VERSION = '2024-04';
const RATE_LIMIT_DELAY = 500; // 500ms delay between requests (2 req/s)

// Helper to delay execution
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

// Helper to make authenticated requests to the Shopify Admin API
async function shopifyFetch(shopDomain: string, accessToken: string, endpoint: string) {
    const url = `${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/${endpoint}`;
    await delay(RATE_LIMIT_DELAY); // Respect rate limit
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
    
    // Extract the 'Link' header for pagination
    const linkHeader = response.headers.get('Link');
    const nextUrl = parseLinkHeader(linkHeader);

    const data = await response.json();
    return { data, nextUrl };
}

// Helper to parse the 'Link' header for pagination
function parseLinkHeader(linkHeader: string | null): string | null {
    if (!linkHeader) return null;
    const links = linkHeader.split(',');
    const nextLink = links.find(link => link.includes('rel="next"'));
    if (!nextLink) return null;
    const match = nextLink.match(/<(.*?)>/);
    return match ? match[1] : null;
}

async function createSyncLog(integrationId: string, syncType: 'products' | 'orders', status: 'started' | 'completed' | 'failed', details: Record<string, any> = {}) {
    const supabase = getServiceRoleClient();
    const { data, error } = await supabase
        .from('sync_logs')
        .insert({
            integration_id: integrationId,
            sync_type: syncType,
            status,
            ...details,
        })
        .select('id')
        .single();
    if (error) {
        logError(error, { context: `Failed to create sync log for integration ${integrationId}` });
    }
    return data?.id;
}


export async function syncProducts(integration: ShopifyIntegration, accessToken: string) {
    const supabase = getServiceRoleClient();
    const logId = await createSyncLog(integration.id, 'products', 'started');
    let allProducts: any[] = [];
    let recordsSynced = 0;
    
    try {
        let nextUrl: string | null = `${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/products.json?limit=250`;

        while (nextUrl) {
            const response = await fetch(nextUrl, {
                headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
            });
             await delay(RATE_LIMIT_DELAY);

            if (!response.ok) {
                const errorBody = await response.text();
                throw new Error(`Shopify API product fetch error (${response.status}): ${errorBody}`);
            }

            const pageData = await response.json();
            allProducts = allProducts.concat(pageData.products);
            nextUrl = parseLinkHeader(response.headers.get('Link'));
        }

        const inventoryToUpsert = allProducts.flatMap(product => 
            product.variants.map((variant: any) => ({
                company_id: integration.company_id,
                sku: variant.sku || `SHOPIFY-${variant.id}`,
                name: variant.title === 'Default Title' ? product.title : `${product.title} - ${variant.title}`,
                quantity: variant.inventory_quantity,
                cost: parseFloat(variant.price),
                category: product.product_type,
                shopify_product_id: product.id,
                shopify_variant_id: variant.id,
            }))
        );
        
        if (inventoryToUpsert.length > 0) {
            const { error: upsertError } = await supabase
                .from('inventory')
                .upsert(inventoryToUpsert, { onConflict: 'company_id, shopify_variant_id' });

            if (upsertError) {
                throw new Error(`Database upsert error: ${upsertError.message}`);
            }
            recordsSynced = inventoryToUpsert.length;
        }

        await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: recordsSynced }).eq('id', logId);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);

    } catch (e: any) {
        logError(e, { context: `Shopify product sync failed for integration ${integration.id}` });
        if (logId) {
            await supabase.from('sync_logs').update({ status: 'failed', completed_at: new Date().toISOString(), error_message: e.message }).eq('id', logId);
        }
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
    }
}
