
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';
import type { Product, ProductVariant } from '@/types';

const RATE_LIMIT_DELAY = 500; // 500ms delay between requests
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function wooCommerceFetch(
    storeUrl: string,
    consumerKey: string,
    consumerSecret: string,
    endpoint: string,
    params: Record<string, string | number> = {}
) {
    const url = new URL(`${storeUrl.replace(/\/$/, "")}/wp-json/wc/v3/${endpoint}`);
    url.searchParams.set('consumer_key', consumerKey);
    url.searchParams.set('consumer_secret', consumerSecret);
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, String(value)));

    const response = await fetch(url.toString());

    if (!response.ok) {
        const errorBody = await response.text();
        throw new Error(`WooCommerce API error (${response.status}): ${errorBody}`);
    }
    return {
        data: await response.json(),
        totalPages: parseInt(response.headers.get('X-WP-TotalPages') || '1', 10),
    };
}


async function syncProducts(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[WooCommerce Sync] Starting product/variant sync for ${integration.shop_name}`);
    let totalProductsSynced = 0;
    let totalVariantsSynced = 0;
    let currentPage = 1;

    while (true) {
        const { data: wooProducts, totalPages } = await wooCommerceFetch(
            integration.shop_domain!,
            credentials.consumerKey,
            credentials.consumerSecret,
            'products',
            { per_page: 50, page: currentPage }
        );
        await delay(RATE_LIMIT_DELAY);

        if (wooProducts.length === 0) break;

        const productsToUpsert: Omit<Product, 'id' | 'created_at' | 'updated_at'>[] = [];
        
        for (const wooProduct of wooProducts) {
             productsToUpsert.push({
                company_id: integration.company_id,
                title: wooProduct.name,
                description: wooProduct.description,
                handle: wooProduct.slug,
                product_type: wooProduct.categories?.[0]?.name,
                tags: wooProduct.tags?.map((t: any) => t.name),
                status: wooProduct.status,
                image_url: wooProduct.images?.[0]?.src,
                external_product_id: String(wooProduct.id),
            });
        }
        
        if (productsToUpsert.length > 0) {
            const { data: upsertedProducts, error: productUpsertError } = await supabase
                .from('products')
                .upsert(productsToUpsert, { onConflict: 'company_id, external_product_id', ignoreDuplicates: false })
                .select('id, external_product_id');

            if (productUpsertError) throw new Error(`Database upsert error for products: ${productUpsertError.message}`);
            totalProductsSynced += upsertedProducts?.length || 0;

            const productIdMap = new Map(upsertedProducts?.map(p => [p.external_product_id, p.id]));

            const variantsToUpsert: Omit<ProductVariant, 'id' | 'created_at' | 'updated_at'>[] = [];
            for (const wooProduct of wooProducts) {
                const internalProductId = productIdMap.get(String(wooProduct.id));
                if (!internalProductId) continue;

                // Handle simple products (no variants)
                if (wooProduct.type === 'simple') {
                    variantsToUpsert.push({
                        product_id: internalProductId,
                        company_id: integration.company_id,
                        sku: wooProduct.sku || `WOO-${wooProduct.id}`,
                        title: null,
                        price: Math.round(parseFloat(wooProduct.price || 0) * 100),
                        cost: null, // WooCommerce does not have a standard cost field
                        inventory_quantity: wooProduct.stock_quantity || 0,
                        external_variant_id: String(wooProduct.id),
                    });
                    continue;
                }

                // Handle variable products
                if (wooProduct.type === 'variable' && wooProduct.variations.length > 0) {
                    for (const variantId of wooProduct.variations) {
                        const { data: variantDetails } = await wooCommerceFetch(
                             integration.shop_domain!,
                             credentials.consumerKey,
                             credentials.consumerSecret,
                             `products/${wooProduct.id}/variations/${variantId}`
                        );
                        await delay(RATE_LIMIT_DELAY);

                        const options = variantDetails.attributes.reduce((acc: any, attr: any) => {
                            acc[attr.name] = attr.option;
                            return acc;
                        }, {});
                        
                        variantsToUpsert.push({
                            product_id: internalProductId,
                            company_id: integration.company_id,
                            sku: variantDetails.sku || `WOO-${variantDetails.id}`,
                            title: variantDetails.attributes.map((a: any) => a.option).join(' / '),
                            option1_name: variantDetails.attributes[0]?.name,
                            option1_value: variantDetails.attributes[0]?.option,
                            option2_name: variantDetails.attributes[1]?.name,
                            option2_value: variantDetails.attributes[1]?.option,
                            option3_name: variantDetails.attributes[2]?.name,
                            option3_value: variantDetails.attributes[2]?.option,
                            price: Math.round(parseFloat(variantDetails.price || 0) * 100),
                            cost: null,
                            inventory_quantity: variantDetails.stock_quantity || 0,
                            external_variant_id: String(variantDetails.id),
                        });
                    }
                }
            }

            if (variantsToUpsert.length > 0) {
                 const { error: variantUpsertError } = await supabase
                    .from('product_variants')
                    .upsert(variantsToUpsert, { onConflict: 'company_id, external_variant_id' });
                    
                if (variantUpsertError) throw new Error(`Database upsert error for variants: ${variantUpsertError.message}`);
                totalVariantsSynced += variantsToUpsert.length;
            }
        }

        if (currentPage >= totalPages) break;
        currentPage++;
    }

    logger.info(`[WooCommerce Sync] Synced ${totalProductsSynced} products and ${totalVariantsSynced} variants for ${integration.shop_name}`);
}


async function syncSales(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[WooCommerce Sync] Starting sales sync for ${integration.shop_name}`);
    let totalOrdersSynced = 0;
    let currentPage = 1;

    while (true) {
         const { data: orders, totalPages } = await wooCommerceFetch(
            integration.shop_domain!,
            credentials.consumerKey,
            credentials.consumerSecret,
            'orders',
            { per_page: 50, page: currentPage }
        );
        await delay(RATE_LIMIT_DELAY);
        
        if (orders.length === 0) break;

        for (const order of orders) {
             const { error } = await supabase.rpc('record_order_from_platform', {
                p_company_id: integration.company_id,
                p_order_payload: order,
                p_platform: 'woocommerce'
            });

            if (error) {
                logError(error, { context: `Failed to record synced WooCommerce order ${order.id}` });
            } else {
                totalOrdersSynced++;
            }
        }

        if (currentPage >= totalPages) break;
        currentPage++;
    }

    logger.info(`[WooCommerce Sync] Synced ${totalOrdersSynced} orders for ${integration.shop_name}`);
}

export async function runWooCommerceFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const credentialsJson = await getSecret(integration.company_id, 'woocommerce');
        if (!credentialsJson || !integration.shop_domain) {
            throw new Error('WooCommerce credentials or store URL are missing.');
        }

        const credentials = JSON.parse(credentialsJson);
        if (!credentials.consumerKey || !credentials.consumerSecret) {
            throw new Error('Invalid WooCommerce credentials format.');
        }

        logger.info(`[Sync] Starting product sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_products' }).eq('id', integration.id);
        await syncProducts(integration, credentials);
        
        logger.info(`[Sync] Starting sales sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_sales' }).eq('id', integration.id);
        await syncSales(integration, credentials);

        logger.info(`[Sync] Full sync completed for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);
        
        await invalidateCompanyCache(integration.company_id, ['dashboard']);
        await refreshMaterializedViews(integration.company_id);

    } catch(e: any) {
        logError(e, { context: `WooCommerce full sync failed for integration ${integration.id}`});
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
