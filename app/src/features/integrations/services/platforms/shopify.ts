
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration, Product, ProductVariant } from '@/types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

const SHOPIFY_API_VERSION = '2024-07';

function parseLinkHeader(linkHeader: string | null): string | null {
    if (!linkHeader) return null;
    const links = linkHeader.split(',');
    const nextLink = links.find(link => link.includes('rel="next"'));
    if (!nextLink) return null;
    const match = nextLink.match(/<(.*?)>/);
    return match ? match[1] : null;
}

export async function syncProducts(integration: Integration, accessToken: string) {
    const supabase = getServiceRoleClient();
    logger.info(`[Shopify Sync] Starting product/variant sync for ${integration.shop_name}`);
    let totalProductsSynced = 0;
    let totalVariantsSynced = 0;

    let nextUrl: string | null = `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/products.json?limit=50`;

    while (nextUrl) {
        const response = await fetch(nextUrl, {
            headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
        });

        if (!response.ok) throw new Error(`Shopify API product fetch error (${response.status}): ${await response.text()}`);

        const pageData = await response.json();
        const productsToUpsert: Omit<Product, 'id' | 'created_at' | 'updated_at'>[] = [];
        

        // First, prepare products for upsert
        for (const shopifyProduct of pageData.products) {
            productsToUpsert.push({
                company_id: integration.company_id,
                title: shopifyProduct.title,
                description: shopifyProduct.body_html,
                handle: shopifyProduct.handle,
                product_type: shopifyProduct.product_type,
                tags: shopifyProduct.tags.split(',').map((t: string) => t.trim()),
                status: shopifyProduct.status,
                image_url: shopifyProduct.image?.src,
                external_product_id: String(shopifyProduct.id),
            });
        }
        
        // Upsert products and get their internal IDs
        if (productsToUpsert.length > 0) {
            const { data: upsertedProducts, error: productUpsertError } = await supabase
                .from('products')
                .upsert(productsToUpsert, { onConflict: 'company_id, external_product_id', ignoreDuplicates: false })
                .select('id, external_product_id');

            if (productUpsertError) throw new Error(`Database upsert error for products: ${productUpsertError.message}`);
            totalProductsSynced += upsertedProducts?.length || 0;

            const productIdMap = new Map(upsertedProducts?.map(p => [p.external_product_id, p.id]));
            
            // Now prepare variants with the correct internal product_id
            const variantsToUpsert: Omit<ProductVariant, 'id' | 'created_at' | 'updated_at'>[] = [];
            for (const shopifyProduct of pageData.products) {
                const internalProductId = productIdMap.get(String(shopifyProduct.id));
                if (!internalProductId) continue;

                for (const variant of shopifyProduct.variants) {
                    variantsToUpsert.push({
                        product_id: internalProductId,
                        company_id: integration.company_id,
                        sku: variant.sku || `SHOPIFY-${variant.id}`,
                        title: variant.title === 'Default Title' ? null : variant.title,
                        option1_name: shopifyProduct.options[0]?.name,
                        option1_value: variant.option1,
                        option2_name: shopifyProduct.options[1]?.name,
                        option2_value: variant.option2,
                        option3_name: shopifyProduct.options[2]?.name,
                        option3_value: variant.option3,
                        barcode: variant.barcode,
                        price: Math.round(parseFloat(variant.price) * 100),
                        compare_at_price: variant.compare_at_price ? Math.round(parseFloat(variant.compare_at_price) * 100) : null,
                        cost: null, // Cost is not available on the variant endpoint directly
                        inventory_quantity: variant.inventory_quantity || 0,
                        external_variant_id: String(variant.id),
                        location: null, // location is not part of this sync
                    });
                }
            }

             // Upsert variants
            if (variantsToUpsert.length > 0) {
                const { error: variantUpsertError } = await supabase
                    .from('product_variants')
                    .upsert(variantsToUpsert, { onConflict: 'company_id, external_variant_id' });
                    
                if (variantUpsertError) throw new Error(`Database upsert error for variants: ${variantUpsertError.message}`);
                totalVariantsSynced += variantsToUpsert.length;
            }
        }
        
        nextUrl = parseLinkHeader(response.headers.get('Link'));
    }
    
    logger.info(`[Shopify Sync] Synced ${totalProductsSynced} products and ${totalVariantsSynced} variants for ${integration.shop_name}`);
}


export async function syncSales(integration: Integration, accessToken: string) {
    const supabase = getServiceRoleClient();
    logger.info(`[Shopify Sync] Starting sales sync for ${integration.shop_name}`);
    let totalOrdersSynced = 0;
    const failedOrders: { id: string; reason: string }[] = [];
    
    let nextUrl: string | null = `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/orders.json?status=any&limit=50`;

    while (nextUrl) {
        const response = await fetch(nextUrl, {
            headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
        });

        if (!response.ok) throw new Error(`Shopify API order fetch error (${response.status}): ${await response.text()}`);

        const pageData = await response.json();
        const orders = pageData.orders;

        if (orders.length === 0) break;
        
        for (const order of orders) {
            const { error } = await supabase.rpc('record_order_from_platform', {
                p_company_id: integration.company_id,
                p_order_payload: order,
                p_platform: 'shopify'
            });

            if (error) {
                const errorMessage = `Failed to record synced Shopify order ${order.id}: ${error.message}`;
                logError(error, { context: errorMessage });
                failedOrders.push({ id: order.id, reason: error.message });
            } else {
                totalOrdersSynced++;
            }
        }
        
        nextUrl = parseLinkHeader(response.headers.get('Link'));
    }

    logger.info(`[Shopify Sync] Synced ${totalOrdersSynced} orders for ${integration.shop_name}. Failed: ${failedOrders.length}.`);
    if (failedOrders.length > 0) {
      throw new Error(`Shopify sales sync completed with ${failedOrders.length} failed orders. Check logs for details.`);
    }
}

export async function runShopifyFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const accessToken = await getSecret(integration.company_id, 'shopify');
        if (!accessToken) throw new Error('Shopify access token is missing.');

        logger.info(`[Sync] Starting product sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_products' }).eq('id', integration.id);
        await syncProducts(integration, accessToken);
        
        logger.info(`[Sync] Starting sales sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_sales' }).eq('id', integration.id);
        await syncSales(integration, accessToken);

        logger.info(`[Sync] Full sync completed for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);
        
        await invalidateCompanyCache(integration.company_id, ['dashboard']);
        await refreshMaterializedViews(integration.company_id);
        
    } catch(e) {
        logError(e, { context: `Shopify sync failed for integration ${integration.id}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
