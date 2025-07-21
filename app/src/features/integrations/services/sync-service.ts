
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { runShopifyFullSync } from './platforms/shopify';
import { runWooCommerceFullSync } from './platforms/woocommerce';
import { runAmazonFbaFullSync } from './platforms/amazon_fba';
import { logger } from '@/lib/logger';
import type { Integration } from '@/types';

/**
 * The main dispatcher for running an integration sync.
 * This function is platform-agnostic. It fetches the integration details,
 * determines the platform, and calls the appropriate platform-specific
 * sync function. It also includes retry logic with exponential backoff.
 * @param integrationId The ID of the integration to sync.
 * @param companyId The ID of the company, for security verification.
 */
export async function runSync(integrationId: string, companyId: string) {
    const MAX_ATTEMPTS = 3;
    const supabase = getServiceRoleClient();

    const { data: initialIntegration, error: fetchError } = await supabase
        .from('integrations')
        .select('*')
        .eq('id', integrationId)
        .eq('company_id', companyId) // Ensure the integration belongs to the specified company.
        .single();

    if (fetchError || !initialIntegration) {
        throw new Error('Integration not found or access is denied.');
    }

    if (initialIntegration.sync_status?.startsWith('syncing')) {
        logger.warn(`[Sync Service] Sync already in progress for integration ${integrationId}. Aborting new request.`);
        return;
    }

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        try {
            await supabase.from('integrations').update({ sync_status: 'syncing', last_sync_at: new Date().toISOString() }).eq('id', integrationId);

            const { data: integration, error: refetchError } = await supabase.from('integrations').select('*').eq('id', integrationId).single();
            if(refetchError || !integration) throw new Error('Could not refetch integration details during sync.');
            
            // This is a final safeguard to ensure we don't operate on the wrong tenant's data.
            if (integration.company_id !== companyId) {
                throw new Error(`CRITICAL: Mismatched company ID during sync job. Integration Company: ${integration.company_id}, Job Company: ${companyId}`);
            }

            switch (integration.platform) {
                case 'shopify':
                    await runShopifyFullSync(integration as Integration);
                    break;
                case 'woocommerce':
                    await runWooCommerceFullSync(integration as Integration);
                    break;
                case 'amazon_fba':
                    await runAmazonFbaFullSync(integration as Integration);
                    break;
                default:
                    throw new Error(`Unsupported integration platform: ${integration.platform}`);
            }
            
            // If sync succeeds, break the loop
            return;

        } catch (e: unknown) {
            logError(e, { context: `Sync failed for integration ${integrationId}, attempt ${attempt}` });
            
            if (attempt < MAX_ATTEMPTS) {
                const delayMs = Math.pow(2, attempt) * 2000;
                logger.info(`[Sync Service] Retrying sync for ${integrationId} in ${delayMs}ms...`);
                await new Promise(resolve => setTimeout(resolve, delayMs));
            } else {
                logger.error(`[Sync Service] Max retries reached for integration ${integrationId}. Marking as failed.`);
                await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integrationId);
                throw new Error(`Sync failed after ${MAX_ATTEMPTS} attempts. Please check the logs.`);
            }
        }
    }
}
