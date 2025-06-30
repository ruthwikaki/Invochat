
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';

const SHOPIFY_API_VERSION = '2024-04';
const RATE_LIMIT_DELAY = 500; // 500ms delay between requests (2 req/s)

// Helper to delay execution
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));


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


export async function syncProducts(integration: Integration, accessToken: string) {
    const supabase = getServiceRoleClient();
    const logId = await createSyncLog(integration.id, 'products', 'started');
    let allProducts: any[] = [];
    let recordsSynced = 0;
    
    try {
        let nextUrl: string | null = `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/products.json?limit=250`;

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
                barcode: variant.barcode,
                shopify_product_id: product.id,
                shopify_variant_id: variant.id,
            }))
        );
        
        if (inventoryToUpsert.length > 0) {
            const { error: upsertError } = await supabase.rpc('batch_upsert_with_transaction', {
                p_table_name: 'inventory',
                p_records: inventoryToUpsert,
                p_conflict_columns: ['company_id', 'shopify_variant_id'],
            });

            if (upsertError) {
                throw new Error(`Database upsert error for products: ${upsertError.message}`);
            }
            recordsSynced = inventoryToUpsert.length;
        }

        if (logId) await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: recordsSynced }).eq('id', logId);
        logger.info(`Successfully synced ${recordsSynced} products for ${integration.shop_name}`);

    } catch (e: any) {
        logError(e, { context: `Shopify product sync failed for integration ${integration.id}` });
        if (logId) {
            await supabase.from('sync_logs').update({ status: 'failed', completed_at: new Date().toISOString(), error_message: e.message }).eq('id', logId);
        }
        throw e; // Re-throw to be caught by the main sync function
    }
}


export async function syncOrders(integration: Integration, accessToken: string) {
  const supabase = getServiceRoleClient();
  const logId = await createSyncLog(integration.id, 'orders', 'started');
  let allOrders: any[] = [];
  let recordsSynced = 0;

  try {
    let nextUrl: string | null = `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/orders.json?status=any&limit=250`;

    while (nextUrl) {
      const response = await fetch(nextUrl, {
        headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
      });
      await delay(RATE_LIMIT_DELAY);

      if (!response.ok) {
        const errorBody = await response.text();
        throw new Error(`Shopify API order fetch error (${response.status}): ${errorBody}`);
      }

      const pageData = await response.json();
      allOrders = allOrders.concat(pageData.orders);
      nextUrl = parseLinkHeader(response.headers.get('Link'));
    }

    if (allOrders.length === 0) {
        logger.info(`No orders to sync for ${integration.shop_name}`);
        if(logId) await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: 0 }).eq('id', logId);
        return;
    }
    
    // Upsert customers first
    const customersToUpsert = allOrders.map(order => ({
        company_id: integration.company_id,
        customer_name: `${order.customer.first_name || ''} ${order.customer.last_name || ''}`.trim() || 'Unknown Customer',
        email: order.customer.email
    })).filter(c => c.customer_name); // Filter out orders without customer names

    if (customersToUpsert.length > 0) {
        await supabase.rpc('batch_upsert_with_transaction', {
            p_table_name: 'customers',
            p_records: customersToUpsert,
            p_conflict_columns: ['company_id', 'customer_name'],
        });
    }

    // Create orders and order_items
    const ordersToInsert = allOrders.map(order => ({
        company_id: integration.company_id,
        sale_date: order.created_at,
        customer_name: `${order.customer.first_name || ''} ${order.customer.last_name || ''}`.trim() || 'Unknown Customer',
        total_amount: order.total_price,
        sales_channel: 'shopify',
        shopify_order_id: order.id,
    })).filter(o => o.customer_name); // Ensure we only create orders with customers
    
    // We must use a direct upsert here because the batch function cannot return IDs needed for foreign keys.
    const { data: createdOrders, error: orderError } = await supabase
        .from('orders')
        .upsert(ordersToInsert, { onConflict: 'company_id, shopify_order_id', ignoreDuplicates: false })
        .select('id, shopify_order_id');

    if (orderError) throw new Error(`Database upsert error for orders: ${orderError.message}`);

    if(!createdOrders) throw new Error("Failed to retrieve created orders after upsert.");

    const orderIdMap = new Map(createdOrders.map(o => [o.shopify_order_id, o.id]));

    const orderItemsToInsert = allOrders.flatMap(order => 
        order.line_items.map((item: any) => ({
            sale_id: orderIdMap.get(order.id),
            sku: item.sku || `SHOPIFY-${item.variant_id}`,
            quantity: item.quantity,
            unit_price: item.price,
        }))
    ).filter(item => item.sale_id); // Filter out items for which order creation might have failed

    if (orderItemsToInsert.length > 0) {
        const { error: itemError } = await supabase.from('order_items').insert(orderItemsToInsert);
        if (itemError) throw new Error(`Database insert error for order items: ${itemError.message}`);
    }

    recordsSynced = allOrders.length;
    if(logId) await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: recordsSynced }).eq('id', logId);
    logger.info(`Successfully synced ${recordsSynced} orders for ${integration.shop_name}`);

  } catch (e: any) {
    logError(e, { context: `Shopify order sync failed for integration ${integration.id}` });
    if (logId) {
      await supabase.from('sync_logs').update({ status: 'failed', completed_at: new Date().toISOString(), error_message: e.message }).eq('id', logId);
    }
    throw e;
  }
}

export async function runShopifyFullSync(integration: Integration, accessToken: string) {
    const supabase = getServiceRoleClient();
    try {
        await Promise.all([
            syncProducts(integration, accessToken),
            syncOrders(integration, accessToken)
        ]);
        
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);
        
        // Invalidate caches and refresh materialized views after a successful sync
        await invalidateCompanyCache(integration.company_id, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(integration.company_id);
    } catch(e) {
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        // Re-throw the error to be handled by the main sync service
        throw e;
    }
}
