
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';

const RATE_LIMIT_DELAY = 500; // 500ms delay between requests
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function wooCommerceFetch(
    storeUrl: string,
    consumerKey: string,
    consumerSecret: string,
    endpoint: string,
    params: Record<string, string> = {}
) {
    const url = new URL(`${storeUrl.replace(/\/$/, "")}/wp-json/wc/v3/${endpoint}`);
    url.searchParams.set('consumer_key', consumerKey);
    url.searchParams.set('consumer_secret', consumerSecret);
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));

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
    let totalRecordsSynced = 0;
    let page = 1;
    let totalPages = 1;

    try {
        do {
            const { data: products } = await wooCommerceFetch(
                integration.shop_domain!,
                credentials.consumerKey,
                credentials.consumerSecret,
                'products',
                { per_page: '100', page: String(page) }
            );

            if (products.length === 0) break;

            const recordsToUpsert = products.map((product: any) => ({
                company_id: integration.company_id,
                sku: product.sku || `WOO-${product.id}`,
                name: product.name,
                quantity: product.stock_quantity ?? 0,
                cost: parseFloat(product.regular_price || 0),
                price: parseFloat(product.price || 0),
                category: product.categories?.[0]?.name,
                source_platform: 'woocommerce',
                external_product_id: String(product.id),
                external_variant_id: String(product.id), // WooCommerce simple products don't have variants in the same way
                last_sync_at: new Date().toISOString(),
            }));
            
            if (recordsToUpsert.length > 0) {
                 const { error } = await supabase.from('inventory').upsert(recordsToUpsert, { onConflict: 'company_id,source_platform,external_product_id' });
                 if (error) throw new Error(`Database upsert error for products: ${error.message}`);
                 totalRecordsSynced += recordsToUpsert.length;
            }
            
            page++;
            await delay(RATE_LIMIT_DELAY);
        } while (page <= totalPages);

        logger.info(`Successfully synced ${totalRecordsSynced} products for ${integration.shop_name}`);

    } catch (e: any) {
        logError(e, { context: `WooCommerce product sync failed for integration ${integration.id}` });
        throw e;
    }
}


async function syncSales(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    const supabase = getServiceRoleClient();
    let totalRecordsSynced = 0;
    let page = 1;
    let totalPages = 1;

    try {
        do {
            const { data: orders, totalPages: pages } = await wooCommerceFetch(
                integration.shop_domain!,
                credentials.consumerKey,
                credentials.consumerSecret,
                'orders',
                { per_page: '100', page: String(page) }
            );
            totalPages = pages;

            if (orders.length === 0) break;
            
            for (const order of orders) {
                const { error } = await supabase.rpc('record_sale_transaction', {
                    p_company_id: integration.company_id,
                    p_user_id: null,
                    p_customer_name: `${order.billing.first_name || ''} ${order.billing.last_name || ''}`.trim() || 'WooCommerce Customer',
                    p_customer_email: order.billing.email,
                    p_payment_method: order.payment_method_title || 'woocommerce',
                    p_notes: `WooCommerce Order #${order.id}`,
                    p_sale_items: order.line_items.map((item: any) => ({
                        sku: item.sku || `WOO-${item.product_id}`,
                        product_name: item.name,
                        quantity: item.quantity,
                        unit_price: parseFloat(item.price),
                        cost_at_time: null,
                    })),
                    p_external_id: String(order.id)
                });
                if (error) {
                    logError(error, { context: `Failed to record synced WooCommerce sale ${order.id}` });
                } else {
                    totalRecordsSynced++;
                }
            }

            page++;
            await delay(RATE_LIMIT_DELAY);
        } while (page <= totalPages);
        
        logger.info(`Successfully synced ${totalRecordsSynced} sales for ${integration.shop_name}`);

    } catch (e: any) {
        logError(e, { context: `WooCommerce sales sync failed for integration ${integration.id}` });
        throw e;
    }
}

export async function runWooCommerceFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        if (!integration.access_token || !integration.shop_domain) {
            throw new Error('WooCommerce credentials or store URL are missing.');
        }

        const credentials = JSON.parse(integration.access_token);
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
        
        await invalidateCompanyCache(integration.company_id, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(integration.company_id);

    } catch(e: any) {
        logError(e, { context: `WooCommerce full sync failed for integration ${integration.id}`});
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
