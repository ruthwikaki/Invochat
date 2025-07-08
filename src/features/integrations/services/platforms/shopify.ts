

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

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

async function createSyncLog(integrationId: string, syncType: 'products' | 'sales', status: 'started' | 'completed' | 'failed', details: Record<string, any> = {}) {
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
    const syncType = 'products';
    const logId = await createSyncLog(integration.id, syncType, 'started');
    let totalRecordsSynced = 0;

    try {
        const { data: syncState } = await supabase
            .from('sync_state')
            .select('last_processed_cursor')
            .eq('integration_id', integration.id)
            .eq('sync_type', syncType)
            .maybeSingle();

        let nextUrl: string | null = syncState?.last_processed_cursor || `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/products.json?limit=250`;

        while (nextUrl) {
            const response = await fetch(nextUrl, {
                headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
            });
            await delay(RATE_LIMIT_DELAY);

            if (!response.ok) throw new Error(`Shopify API product fetch error (${response.status}): ${await response.text()}`);

            const pageData = await response.json();
            const recordsToUpsert: any[] = [];

            for (const product of pageData.products) {
                for (const variant of product.variants) {
                    recordsToUpsert.push({
                        company_id: integration.company_id,
                        sku: variant.sku || `SHOPIFY-${variant.id}`,
                        name: variant.title === 'Default Title' ? product.title : `${product.title} - ${variant.title}`,
                        quantity: variant.inventory_quantity, // Direct sync from Shopify
                        cost: parseFloat(variant.price),
                        price: parseFloat(variant.price),
                        category: product.product_type,
                        barcode: variant.barcode,
                        source_platform: 'shopify',
                        external_product_id: String(product.id),
                        external_variant_id: String(variant.id),
                        external_quantity: variant.inventory_quantity, // Keep track of what Shopify says
                        last_sync_at: new Date().toISOString(),
                    });
                }
            }

            if (recordsToUpsert.length > 0) {
                 const { error: upsertError } = await supabase.from('inventory').upsert(recordsToUpsert, { onConflict: 'company_id,source_platform,external_variant_id' });
                 if (upsertError) throw new Error(`Database upsert error for products: ${upsertError.message}`);
                 totalRecordsSynced += recordsToUpsert.length;
            }
            
            nextUrl = parseLinkHeader(response.headers.get('Link'));
            
            // Checkpoint progress
            await supabase.from('sync_state').upsert({
                integration_id: integration.id,
                sync_type: syncType,
                last_processed_cursor: nextUrl,
                last_update: new Date().toISOString(),
            });
        }
        
        // On success, clean up sync state for this type
        await supabase.from('sync_state').delete().eq('integration_id', integration.id).eq('sync_type', syncType);
        if (logId) await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: totalRecordsSynced }).eq('id', logId);
        logger.info(`Successfully synced ${totalRecordsSynced} products for ${integration.shop_name}`);

    } catch (e: any) {
        logError(e, { context: `Shopify product sync failed for integration ${integration.id}` });
        if (logId) await supabase.from('sync_logs').update({ status: 'failed', completed_at: new Date().toISOString(), error_message: e.message }).eq('id', logId);
        throw e;
    }
}


export async function syncSales(integration: Integration, accessToken: string) {
  const supabase = getServiceRoleClient();
  const syncType = 'sales';
  const logId = await createSyncLog(integration.id, syncType, 'started');
  let totalRecordsSynced = 0;

  try {
     const { data: syncState } = await supabase
            .from('sync_state')
            .select('last_processed_cursor')
            .eq('integration_id', integration.id)
            .eq('sync_type', syncType)
            .maybeSingle();

    let nextUrl: string | null = syncState?.last_processed_cursor || `https://${integration.shop_domain}/admin/api/${SHOPIFY_API_VERSION}/orders.json?status=any&limit=250`;

    while (nextUrl) {
      const response = await fetch(nextUrl, {
        headers: { 'X-Shopify-Access-Token': accessToken, 'Content-Type': 'application/json' },
      });
      await delay(RATE_LIMIT_DELAY);

      if (!response.ok) throw new Error(`Shopify API order fetch error (${response.status}): ${await response.text()}`);

      const pageData = await response.json();
      const allOrders = pageData.orders;

      if (allOrders.length > 0) {
        
        for (const order of allOrders) {
            const { error } = await supabase.rpc('record_sale_transaction', {
                p_company_id: integration.company_id,
                p_user_id: null, // System-generated sale
                p_customer_name: `${order.customer?.first_name || ''} ${order.customer?.last_name || ''}`.trim() || 'Shopify Customer',
                p_customer_email: order.customer?.email,
                p_payment_method: order.gateway || 'shopify',
                p_notes: `Shopify Order #${order.order_number}`,
                p_sale_items: order.line_items.map((item: any) => ({
                    sku: item.sku || `SHOPIFY-${item.variant_id}`,
                    product_name: item.name,
                    quantity: item.quantity,
                    unit_price: parseFloat(item.price),
                    cost_at_time: null, // We can't know cost at time of sale from here easily
                })),
                p_external_id: String(order.id)
            });

            if (error) {
                 logError(error, { context: `Failed to record synced Shopify sale ${order.id}` });
            } else {
                 totalRecordsSynced++;
            }
        }
      }
      
      nextUrl = parseLinkHeader(response.headers.get('Link'));
      
      await supabase.from('sync_state').upsert({
          integration_id: integration.id, sync_type: syncType,
          last_processed_cursor: nextUrl, last_update: new Date().toISOString(),
      });
    }

    await supabase.from('sync_state').delete().eq('integration_id', integration.id).eq('sync_type', syncType);
    if(logId) await supabase.from('sync_logs').update({ status: 'completed', completed_at: new Date().toISOString(), records_synced: totalRecordsSynced }).eq('id', logId);
    logger.info(`Successfully synced ${totalRecordsSynced} sales for ${integration.shop_name}`);

  } catch (e: any) {
    logError(e, { context: `Shopify sales sync failed for integration ${integration.id}` });
    if (logId) await supabase.from('sync_logs').update({ status: 'failed', completed_at: new Date().toISOString(), error_message: e.message }).eq('id', logId);
    throw e;
  }
}

export async function runShopifyFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const accessToken = await getSecret(integration.company_id, 'shopify');
        if (!accessToken) {
            throw new Error('Shopify access token is missing for this integration.');
        }

        logger.info(`[Sync] Starting product sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_products' }).eq('id', integration.id);
        await syncProducts(integration, accessToken);
        
        logger.info(`[Sync] Starting sales sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_sales' }).eq('id', integration.id);
        await syncSales(integration, accessToken);

        logger.info(`[Sync] Full sync completed for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);
        
        await invalidateCompanyCache(integration.company_id, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(integration.company_id);
    } catch(e) {
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
