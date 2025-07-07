
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
                cost: parseFloat(product.price || 0),
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


async function syncOrders(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
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

            const customersToUpsert = orders.map((order: any) => ({
                company_id: integration.company_id,
                platform: 'woocommerce',
                external_id: String(order.customer_id),
                customer_name: `${order.billing.first_name || ''} ${order.billing.last_name || ''}`.trim() || 'Guest Customer',
                email: order.billing.email,
            }));
            
            if (customersToUpsert.length > 0) {
                 const { data: upsertedCustomers, error: customerError } = await supabase
                    .from('customers').upsert(customersToUpsert, { onConflict: 'company_id, platform, external_id' }).select('id, external_id');
                if (customerError) throw new Error(`Database upsert error for customers: ${customerError.message}`);

                const customerIdMap = new Map(upsertedCustomers.map(c => [c.external_id, c.id]));
                const ordersToInsert = orders.map((order: any) => ({
                    company_id: integration.company_id,
                    customer_id: customerIdMap.get(String(order.customer_id)),
                    sale_date: order.date_created_gmt,
                    total_amount: order.total,
                    sales_channel: 'woocommerce',
                    platform: 'woocommerce',
                    external_id: String(order.id),
                }));

                const { data: createdOrders, error: orderError } = await supabase
                    .from('orders').upsert(ordersToInsert, { onConflict: 'company_id, platform, external_id' }).select('id, external_id');
                if (orderError) throw new Error(`Database upsert error for orders: ${orderError.message}`);

                const orderIdMap = new Map(createdOrders.map(o => [o.external_id, o.id]));
                const orderItemsToInsert = orders.flatMap((order: any) => 
                    order.line_items.map((item: any) => ({
                        sale_id: orderIdMap.get(String(order.id)),
                        sku: item.sku || `WOO-${item.product_id}`,
                        quantity: item.quantity,
                        unit_price: item.price,
                    }))
                ).filter((item: any) => item.sale_id);

                if (orderItemsToInsert.length > 0) {
                    const { error: itemError } = await supabase.from('order_items').insert(orderItemsToInsert);
                    if (itemError) throw new Error(`Database insert error for order items: ${itemError.message}`);
                }

                for (const order of createdOrders) {
                    const { error: processError } = await supabase.rpc('process_sales_order_inventory', { p_order_id: order.id, p_company_id: integration.company_id });
                    if (processError) logError(processError, { context: `Failed to process inventory for synced order ${order.external_id}` });
                }
            }
            totalRecordsSynced += orders.length;
            page++;
            await delay(RATE_LIMIT_DELAY);
        } while (page <= totalPages);
        
        logger.info(`Successfully synced ${totalRecordsSynced} orders for ${integration.shop_name}`);

    } catch (e: any) {
        logError(e, { context: `WooCommerce order sync failed for integration ${integration.id}` });
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
        
        logger.info(`[Sync] Starting order sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_orders' }).eq('id', integration.id);
        await syncOrders(integration, credentials);

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
