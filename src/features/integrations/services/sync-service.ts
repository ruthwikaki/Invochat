

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
 * sync function. It also includes retry logic with exponential backoff.
 * @param integrationId The ID of the integration to sync.
 * @param companyId The ID of the company, for security verification.
 * @param attempt The current retry attempt number.
 */
export async function runSync(integrationId: string, companyId: string, attempt = 1) {
    const MAX_ATTEMPTS = 3;
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
    if (integration.sync_status?.startsWith('syncing') && attempt === 1) {
        logger.warn(`[Sync Service] Sync already in progress for integration ${integrationId}. Aborting new request.`);
        return;
    }

    try {
        // 2. Set status to 'syncing' immediately to give user feedback.
        await supabase.from('integrations').update({ sync_status: 'syncing', last_sync_at: new Date().toISOString() }).eq('id', integrationId);

        // 3. Dispatch to the correct platform-specific service.
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
        logError(e, { context: `Sync failed for integration ${integration.id}, attempt ${attempt}` });
        
        // On failure, do not clear the cursor state. This allows the sync
        // to be potentially retried from where it left off.
        
        if (attempt < MAX_ATTEMPTS) {
            const delayMs = Math.pow(2, attempt) * 2000; // Exponential backoff starts at 2s, then 4s, then 8s
            logger.info(`[Sync Service] Retrying sync for ${integration.id} in ${delayMs}ms...`);
            await new Promise(resolve => setTimeout(resolve, delayMs));
            // IMPORTANT: Use 'return' here to correctly chain the promise from the recursive call.
            return runSync(integrationId, companyId, attempt + 1);
        } else {
            logger.error(`[Sync Service] Max retries reached for integration ${integration.id}. Marking as failed.`);
            // Update status to failed only after all retries are exhausted
            await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integration.id);
            // Re-throw the error to be caught by the original caller if needed
            throw new Error(`Sync failed after ${MAX_ATTEMPTS} attempts. Please check the logs.`);
        }
    }
}
