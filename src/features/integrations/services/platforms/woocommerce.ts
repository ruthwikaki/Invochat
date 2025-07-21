
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration, Product, ProductVariant } from '@/types';
import { refreshMaterializedViews, invalidateCompanyCache } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

async function wooCommerceFetch(
    storeUrl: string | null,
    consumerKey: string,
    consumerSecret: string,
    endpoint: string,
    params: Record<string, string | number> = {}
) {
    if (!storeUrl) {
        throw new Error("WooCommerce store URL is missing for the fetch request.");
    }
    const url = new URL(`${storeUrl.replace(/\/$/, "")}/wp-json/wc/v3/${endpoint}`);
    url.searchParams.set('consumer_key', consumerKey);
    url.searchParams.set('consumer_secret', consumerSecret);
    Object.entries(params).forEach(([key, value]) => { url.searchParams.set(key, String(value)); });

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

// Type guard to check if an object is a valid WooCommerce product for our needs.
function isVariableProduct(p: unknown): p is { id: number; type: 'variable', variations: unknown[] } {
    return (
        typeof p === 'object' &&
        p !== null &&
        'type' in p &&
        (p as { type: unknown }).type === 'variable' &&
        'variations' in p &&
        Array.isArray((p as { variations: unknown }).variations)
    );
}

async function syncProducts(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[WooCommerce Sync] Starting product/variant sync for ${integration.shop_name}`);
    let totalProductsSynced = 0;
    let totalVariantsSynced = 0;
    let currentPage = 1;
    let totalPages = 1;

    do {
        const { data: wooProducts, totalPages: newTotalPages } = await wooCommerceFetch(
            integration.shop_domain,
            credentials.consumerKey,
            credentials.consumerSecret,
            'products',
            { per_page: 50, page: currentPage }
        );
        totalPages = newTotalPages;

        if (wooProducts.length === 0) break;

        const productsToUpsert: Omit<Product, 'id' | 'created_at' | 'updated_at'>[] = [];
        
        for (const wooProduct of wooProducts) {
             productsToUpsert.push({
                company_id: integration.company_id,
                title: wooProduct.name,
                description: wooProduct.description,
                handle: wooProduct.slug,
                product_type: wooProduct.categories?.[0]?.name,
                tags: wooProduct.tags?.map((t: { name: string }) => t.name),
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

            const variableProductIds = (wooProducts as unknown[]).filter(isVariableProduct).map((p) => p.id);
            const allVariations: unknown[] = [];
            
            if (variableProductIds.length > 0) {
                 const variationPromises = variableProductIds.map(productId => 
                    wooCommerceFetch(
                         integration.shop_domain,
                         credentials.consumerKey,
                         credentials.consumerSecret,
                         `products/${productId}/variations`,
                         { per_page: 100 }
                    ).then(res => res.data.map((v: unknown) => ({ ...(v as object), parent_id: productId })))
                );
                const results = await Promise.all(variationPromises);
                results.forEach(vars => {
                    allVariations.push(...vars);
                });
            }
            
            for (const wooProduct of wooProducts as { id: number; type: string; sku: string; stock_quantity: number | null, name: string, description: string, slug: string, categories: {name: string}[], tags: {name: string}[], status: string, images: {src: string}[], price: string }[]) {
                const internalProductId = productIdMap.get(String(wooProduct.id));
                if (!internalProductId) continue;

                if (wooProduct.type === 'simple') {
                    variantsToUpsert.push({
                        product_id: internalProductId,
                        company_id: integration.company_id,
                        sku: wooProduct.sku || `WOO-${wooProduct.id}`,
                        title: null,
                        price: Math.round(parseFloat((wooProduct as unknown as { price: string }).price || '0') * 100),
                        cost: null,
                        inventory_quantity: wooProduct.stock_quantity === null ? 0 : wooProduct.stock_quantity,
                        external_variant_id: String(wooProduct.id),
                        location: null,
                        barcode: null,
                        compare_at_price: null,
                        option1_name: null,
                        option1_value: null,
                        option2_name: null,
                        option2_value: null,
                        option3_name: null,
                        option3_value: null,
                    });
                    continue;
                }
            }

            for (const variantDetails of allVariations) {
                const variant = variantDetails as { id: number; parent_id: number; sku: string; attributes: { name: string; option: string }[]; price: string; stock_quantity: number | null; };
                const internalProductId = productIdMap.get(String(variant.parent_id));
                if (!internalProductId) continue;

                variantsToUpsert.push({
                    product_id: internalProductId,
                    company_id: integration.company_id,
                    sku: variant.sku || `WOO-${variant.id}`,
                    title: variant.attributes.map((a) => a.option).join(' / '),
                    option1_name: variant.attributes[0]?.name,
                    option1_value: variant.attributes[0]?.option,
                    option2_name: variant.attributes[1]?.name,
                    option2_value: variant.attributes[1]?.option,
                    option3_name: variant.attributes[2]?.name,
                    option3_value: variant.attributes[2]?.option,
                    price: Math.round(parseFloat(variant.price || '0') * 100),
                    cost: null,
                    barcode: null,
                    compare_at_price: null,
                    inventory_quantity: variant.stock_quantity === null ? 0 : variant.stock_quantity,
                    external_variant_id: String(variant.id),
                    location: null,
                });
            }

            if (variantsToUpsert.length > 0) {
                 const { error: variantUpsertError } = await supabase
                    .from('product_variants')
                    .upsert(variantsToUpsert, { onConflict: 'company_id, external_variant_id' });
                    
                if (variantUpsertError) throw new Error(`Database upsert error for variants: ${variantUpsertError.message}`);
                totalVariantsSynced += variantsToUpsert.length;
            }
        }
        currentPage++;
    } while (currentPage <= totalPages);

    logger.info(`[WooCommerce Sync] Synced ${totalProductsSynced} products and ${totalVariantsSynced} variants for ${integration.shop_name}`);
}


async function syncSales(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[WooCommerce Sync] Starting sales sync for ${integration.shop_name}`);
    let totalOrdersSynced = 0;
    const failedOrders: { id: string; reason: string }[] = [];
    let currentPage = 1;
    let totalPages = 1;

    do {
         const { data: orders, totalPages: newTotalPages } = await wooCommerceFetch(
            integration.shop_domain,
            credentials.consumerKey,
            credentials.consumerSecret,
            'orders',
            { per_page: 50, page: currentPage }
        );
        totalPages = newTotalPages;
        
        if (orders.length === 0) break;

        for (const order of orders) {
             const { error } = await supabase.rpc('record_order_from_platform', {
                p_company_id: integration.company_id,
                p_order_payload: order,
                p_platform: 'woocommerce'
            });

            if (error) {
                const errorMessage = `Failed to record synced WooCommerce order ${order.id}: ${error.message}`;
                logError(error, { context: errorMessage });
                failedOrders.push({ id: order.id, reason: error.message });
            } else {
                totalOrdersSynced++;
            }
        }
        currentPage++;
    } while (currentPage <= totalPages);

    logger.info(`[WooCommerce Sync] Synced ${totalOrdersSynced} orders for ${integration.shop_name}. Failed: ${failedOrders.length}`);
     if (failedOrders.length > 0) {
      throw new Error(`WooCommerce sales sync completed with ${failedOrders.length} failed orders. Check logs for details.`);
    }
}

export async function runWooCommerceFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const credentialsJson = await getSecret(integration.company_id, 'woocommerce');
        if (!credentialsJson) {
            throw new Error('WooCommerce credentials are missing.');
        }
        if (!integration.shop_domain) {
            throw new Error('WooCommerce store URL is missing.');
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

    } catch(e: unknown) {
        logError(e, { context: `WooCommerce full sync failed for integration ${integration.id}`});
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
