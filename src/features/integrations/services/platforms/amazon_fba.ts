
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import type { Integration } from '../../types';
import { invalidateCompanyCache, refreshMaterializedViews } from '@/services/database';
import { logger } from '@/lib/logger';
import { getSecret } from '../encryption';

// --- DYNAMIC SIMULATION FOR AMAZON FBA ---
// Amazon's real SP-API is complex and requires a full OAuth flow.
// To make this integration demonstrable, we dynamically generate mock data
// instead of using a static mock array. This simulates a real sync.

function generateSimulatedProducts(count: number): any[] {
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

function generateSimulatedOrders(products: any[], count: number): any[] {
    const orders = [];
    for (let i = 1; i <= count; i++) {
        const orderId = `FBA-SIM-ORD-${Date.now() + i}`;
        const numItems = Math.floor(Math.random() * 3) + 1;
        const line_items = [];
        let total_price = 0;
        for (let j = 0; j < numItems; j++) {
            const product = products[Math.floor(Math.random() * products.length)];
            const quantity = Math.floor(Math.random() * 2) + 1;
            line_items.push({
                sku: product.sku,
                name: product.name,
                quantity: quantity,
                price: product.price,
            });
            total_price += product.price * quantity;
        }
        orders.push({
            id: orderId,
            customer: { first_name: 'Simulated', last_name: 'Customer', email: `fba.customer+${Date.now() + i}@example.com` },
            total_price: total_price.toFixed(2),
            line_items,
        });
    }
    return orders;
}

async function syncProducts(integration: Integration, credentials: { sellerId: string; authToken: string }) {
    const supabase = getServiceRoleClient();
    logger.info(`[Sync Simulation] Starting Amazon FBA product sync for Seller ID: ${credentials.sellerId}`);

    const simulatedProducts = generateSimulatedProducts(15); // Generate 15 sample products

    const recordsToUpsert = simulatedProducts.map(product => ({
        company_id: integration.company_id,
        sku: product.sku,
        name: product.name,
        quantity: product.inventory_quantity,
        cost: Math.round(parseFloat(product.cost_of_goods) * 100),
        price: Math.round(parseFloat(product.price) * 100),
        category: product.categories[0]?.name || 'Uncategorized',
        source_platform: 'amazon_fba',
        external_product_id: product.id,
        last_sync_at: new Date().toISOString(),
    }));

    if (recordsToUpsert.length > 0) {
        const { error: upsertError } = await supabase.from('inventory').upsert(recordsToUpsert, { onConflict: 'company_id,source_platform,external_product_id' });
        if (upsertError) throw new Error(`Database upsert error for FBA products: ${upsertError.message}`);
    }
    
    logger.info(`Successfully synced ${recordsToUpsert.length} simulated products for ${integration.shop_name}`);
    return simulatedProducts;
}

async function syncSales(integration: Integration, credentials: { sellerId: string; authToken: string }, products: any[]) {
    const supabase = getServiceRoleClient();
    logger.info(`[Sync Simulation] Starting Amazon FBA sales sync for Seller ID: ${credentials.sellerId}`);
    
    const simulatedOrders = generateSimulatedOrders(products, 5); // Generate 5 sample orders
    let totalRecordsSynced = 0;

    for (const order of simulatedOrders) {
        const itemsWithCost = order.line_items.map((item: any) => {
            const product = products.find(p => p.sku === item.sku);
            return {
                ...item,
                cost_at_time: product ? Math.round(parseFloat(product.cost_of_goods) * 100) : 0,
            };
        });

        const { error } = await supabase.rpc('record_sale_transaction', {
            p_company_id: integration.company_id,
            p_user_id: null,
            p_customer_name: `${order.customer.first_name} ${order.customer.last_name}`,
            p_customer_email: order.customer.email,
            p_payment_method: 'amazon_fba',
            p_notes: `Amazon Order #${order.id}`,
            p_sale_items: itemsWithCost.map((item: any) => ({
                sku: item.sku,
                product_name: item.name,
                quantity: item.quantity,
                unit_price: Math.round(parseFloat(item.price) * 100),
                cost_at_time: item.cost_at_time,
            })),
            p_external_id: order.id
        });

        if (error) {
            logError(error, { context: `Failed to record synced FBA sale ${order.id}` });
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

    } catch (e: any) {
        logError(e, { context: `Amazon FBA sync failed for integration ${integration.id}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
        throw e;
    }
}
