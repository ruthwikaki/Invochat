
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '@/types';
import { refreshMaterializedViews } from '@/services/database';
import { invalidateCompanyCache } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

// --- DYNAMIC SIMULATION FOR AMAZON FBA ---
// Amazon's real SP-API is complex and requires a full OAuth flow.
// To make this integration demonstrable, we dynamically generate mock data
// instead of using a static mock array. This simulates a real sync.

function generateSimulatedProducts(count: number): unknown[] {
    const products = [];
    for (let i = 1; i <= count; i++) {
        const id = `FBA-SIM-${String(i).padStart(3, '0')}`;
        products.push({
            id,
            sku: id,
            name: `Simulated FBA Product #${i}`,
            inventory_quantity: Math.floor(Math.random() * 200) + 50,
            price: (Math.random() * 50 + 10).toFixed(2),
            cost_of_goods: (Math.random() * 25 + 5).toFixed(2),
            categories: [{ name: 'Simulated Goods' }],
        });
    }
    return products;
}

function generateSimulatedOrders(products: unknown[], count: number): unknown[] {
    const orders = [];
    for (let i = 1; i <= count; i++) {
        const orderId = `FBA-SIM-ORD-${Date.now() + i}`;
        const numItems = Math.floor(Math.random() * 3) + 1;
        const line_items = [];
        let total_price = 0;
        for (let j = 0; j < numItems; j++) {
            const product = products[Math.floor(Math.random() * products.length)] as Record<string, unknown>;
            const quantity = Math.floor(Math.random() * 2) + 1;
            line_items.push({
                sku: product.sku,
                name: product.name,
                quantity: quantity,
                price: product.price,
            });
            total_price += (product.price as number) * quantity;
        }
        orders.push({
            id: orderId,
            customer: { first_name: 'Simulated', last_name: 'Customer', email: `fba.customer+${Date.now() + i}@example.com` },
            total_price: total_price.toFixed(2),
            line_items,
            created_at: new Date(Date.now() - i * 3600000).toISOString()
        });
    }
    return orders;
}

async function syncProducts(integration: Integration, credentials: { sellerId: string; authToken: string }) {
    logger.info(`[Sync Simulation] Starting Amazon FBA product sync for Seller ID: ${credentials.sellerId}`);

    const simulatedProducts = generateSimulatedProducts(15); // Generate 15 sample products
    logger.info(`Successfully synced ${simulatedProducts.length} simulated products for ${integration.shop_name}`);
    return simulatedProducts;
}

async function syncSales(integration: Integration, credentials: { sellerId: string; authToken: string }, products: unknown[]) {
    const supabase = getServiceRoleClient();
    logger.info(`[Sync Simulation] Starting Amazon FBA sales sync for Seller ID: ${credentials.sellerId}`);
    
    const simulatedOrders = generateSimulatedOrders(products, 5); // Generate 5 sample orders
    let totalRecordsSynced = 0;

    for (const order of (simulatedOrders as Record<string, unknown>[])) {
        const p_order_payload = {
            id: order.id,
            ...order
        };
        const { error } = await supabase.rpc('record_order_from_platform', {
            p_company_id: integration.company_id,
            p_order_payload: p_order_payload,
            p_platform: 'amazon_fba'
        });

        if (error) {
            logError(error, { context: `Failed to record synced FBA sale ${String(order.id)}` });
        } else {
            totalRecordsSynced++;
        }
    }
    
    logger.info(`Successfully synced ${totalRecordsSynced} simulated sales for ${integration.shop_name}`);
}

export async function runAmazonFbaFullSync(integration: Integration) {
    const supabase = getServiceRoleClient();
    try {
        const credentialsJson = await getSecret(integration.company_id, 'amazon_fba');
        if (!credentialsJson) {
            throw new Error('Could not retrieve Amazon FBA credentials.');
        }
        
        const credentials = JSON.parse(credentialsJson);
        
        logger.info(`[Sync] Starting product sync simulation for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_products' }).eq('id', integration.id);
        const products = await syncProducts(integration, credentials);

        logger.info(`[Sync] Starting sales sync simulation for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'syncing_sales' }).eq('id', integration.id);
        await syncSales(integration, credentials, products);

        logger.info(`[Sync] Full sync simulation completed for ${integration.shop_name}`);
        await supabase.from('integrations').update({ sync_status: 'success', last_sync_at: new Date().toISOString() }).eq('id', integration.id);

        await invalidateCompanyCache(integration.company_id, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(integration.company_id);

    } catch (e: unknown) {
        logError(e, { context: `Amazon FBA sync failed for integration ${integration.id}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
