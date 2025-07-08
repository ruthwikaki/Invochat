
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

// Since this is a simulation, we'll create some mock data.
const MOCK_FBA_PRODUCTS = [
    { sku: 'FBA-PROD-001', name: 'Premium FBA Widget', stock: 150, price: 29.99, category: 'Widgets' },
    { sku: 'FBA-PROD-002', name: 'Standard FBA Gadget', stock: 300, price: 19.99, category: 'Gadgets' },
];

const MOCK_FBA_ORDERS = [
    { id: 'FBA-ORD-101', customer: { name: 'John Doe', email: 'john.doe.fba@example.com' }, total: 49.98, items: [{ sku: 'FBA-PROD-002', name: 'Standard FBA Gadget', quantity: 2, price: 19.99 }, { sku: 'FBA-PROD-001', name: 'Premium FBA Widget', quantity: 1, price: 29.99 }] },
];


async function syncProducts(integration: Integration, credentials: { sellerId: string; authToken: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[Sync Placeholder] Starting Amazon FBA product sync for Seller ID: ${credentials.sellerId}`);

    const recordsToUpsert = MOCK_FBA_PRODUCTS.map(product => ({
        company_id: integration.company_id,
        sku: product.sku,
        name: product.name,
        quantity: product.stock,
        cost: product.price * 0.5, // Assume 50% cost for demo
        price: product.price,
        category: product.category,
        source_platform: 'amazon_fba',
        external_product_id: product.sku,
        external_variant_id: product.sku,
        last_sync_at: new Date().toISOString(),
    }));

    if (recordsToUpsert.length > 0) {
        const { error: upsertError } = await supabase.from('inventory').upsert(recordsToUpsert, { onConflict: 'company_id,source_platform,external_product_id' });
        if (upsertError) throw new Error(`Database upsert error for FBA products: ${upsertError.message}`);
    }
    
    logger.info(`Successfully synced ${recordsToUpsert.length} products for ${integration.shop_name}`);
}

async function syncSales(integration: Integration, credentials: { sellerId: string; authToken: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[Sync Placeholder] Starting Amazon FBA sales sync for Seller ID: ${credentials.sellerId}`);
    let totalRecordsSynced = 0;

    for (const order of MOCK_FBA_ORDERS) {
        const { error } = await supabase.rpc('record_sale_transaction', {
            p_company_id: integration.company_id,
            p_user_id: null,
            p_customer_name: order.customer.name,
            p_customer_email: order.customer.email,
            p_payment_method: 'amazon_fba',
            p_notes: `Amazon Order #${order.id}`,
            p_sale_items: order.items.map(item => ({
                sku: item.sku,
                product_name: item.name,
                quantity: item.quantity,
                unit_price: item.price,
                cost_at_time: null,
            })),
            p_external_id: order.id
        });

        if (error) {
            logError(error, { context: `Failed to record synced FBA sale ${order.id}` });
        } else {
            totalRecordsSynced++;
        }
    }
    
    logger.info(`Successfully synced ${totalRecordsSynced} sales for ${integration.shop_name}`);
}

export async function runAmazonFbaFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const credentialsJson = await getSecret(integration.company_id, 'amazon_fba');
        if (!credentialsJson) {
            throw new Error('Could not retrieve Amazon FBA credentials.');
        }
        
        const credentials = JSON.parse(credentialsJson);
        
        logger.info(`[Sync] Starting product sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_products' }).eq('id', integration.id);
        await syncProducts(integration, credentials);

        logger.info(`[Sync] Starting sales sync for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_sales' }).eq('id', integration.id);
        await syncSales(integration, credentials);

        logger.info(`[Sync] Full sync simulation completed for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);

        await invalidateCompanyCache(integration.company_id, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(integration.company_id);

    } catch (e: any) {
        logError(e, { context: `Amazon FBA sync failed for integration ${integration.id}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
