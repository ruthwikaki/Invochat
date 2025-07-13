

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

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
    // This function needs to be rewritten to handle the new product/variant schema
    logger.warn(`[WooCommerce Sync] Product sync is not yet implemented for the new schema.`);
}


async function syncSales(integration: Integration, credentials: { consumerKey: string, consumerSecret: string }) {
    // This function needs to be rewritten to handle the new order schema
    logger.warn(`[WooCommerce Sync] Sales sync is not yet implemented for the new schema.`);
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

    } catch(e: any) {
        logError(e, { context: `WooCommerce full sync failed for integration ${integration.id}`});
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
