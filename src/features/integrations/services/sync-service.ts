
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { runShopifyFullSync } from './platforms/shopify';
import { runWooCommerceFullSync } from './platforms/woocommerce';
import { runAmazonFbaFullSync } from './platforms/amazon_fba';
import { logger } from '@/lib/logger';
import type { Integration } from '../types';

/**
 * The main dispatcher for running an integration sync.
 * This function is platform-agnostic. It fetches the integration details,
 * determines the platform, and calls the appropriate platform-specific
 * sync function.
 * @param integrationId The ID of the integration to sync.
 * @param companyId The ID of the company, for security verification.
 */
export async function runSync(integrationId: string, companyId: string) {
    const supabase = getServiceRoleClient();

    // 1. Fetch integration details to verify ownership and get platform type.
    const { data: integration, error: fetchError } = await supabase
        .from('integrations')
        .select('*')
        .eq('id', integrationId)
        .eq('company_id', companyId)
        .single();

    if (fetchError || !integration) {
        throw new Error('Integration not found or access is denied.');
    }

    // Concurrency Check: Prevent starting a new sync if one is already running.
    if (integration.sync_status?.startsWith('syncing')) {
        logger.warn(`[Sync Service] Sync already in progress for integration ${integrationId}. Aborting new request.`);
        return;
    }

    // 2. Set status to 'syncing' immediately to give user feedback.
    await supabase.from('integrations').update({ sync_status: 'syncing', last_sync_at: new Date().toISOString() }).eq('id', integrationId);

    try {
        // 3. Dispatch to the correct platform-specific service.
        // Each service is now responsible for fetching its own credentials.
        switch (integration.platform) {
            case 'shopify':
                await runShopifyFullSync(integration);
                break;
            case 'woocommerce':
                await runWooCommerceFullSync(integration);
                break;
            case 'amazon_fba':
                await runAmazonFbaFullSync(integration);
                break;
            default:
                throw new Error(`Unsupported integration platform: ${integration.platform}`);
        }
    } catch (e: any) {
        // If any part of the sync fails, log it and update the status.
        logError(e, { context: `Full sync failed for integration ${integration.id}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
    }
}
