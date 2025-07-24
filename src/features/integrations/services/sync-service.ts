

'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { runShopifyFullSync } from './platforms/shopify';
import { runWooCommerceFullSync } from './platforms/woocommerce';
import { runAmazonFbaFullSync } from './platforms/amazon_fba';
import { logger } from '@/lib/logger';
import type { Integration } from '@/types';
import { retry } from '@/lib/async-utils';

/**
 * The main dispatcher for running an integration sync.
 * This function is platform-agnostic. It fetches the integration details,
 * determines the platform, and calls the appropriate platform-specific
 * sync function. It now uses a robust retry mechanism.
 * @param integrationId The ID of the integration to sync.
 * @param companyId The ID of the company, for security verification.
 */
export async function runSync(integrationId: string, companyId: string) {
    const supabase = getServiceRoleClient();

    const { data: initialIntegration, error: fetchError } = await supabase
        .from('integrations')
        .select('*')
        .eq('id', integrationId)
        .eq('company_id', companyId)
        .single();

    if (fetchError || !initialIntegration) {
        throw new Error('Integration not found or access is denied.');
    }

    if (initialIntegration.sync_status?.startsWith('syncing')) {
        logger.warn(`[Sync Service] Sync already in progress for integration ${integrationId}. Aborting new request.`);
        return;
    }

    const syncOperation = async () => {
        await supabase.from('integrations').update({ sync_status: 'syncing', last_sync_at: new Date().toISOString() }).eq('id', integrationId);

        const { data: integration, error: refetchError } = await supabase.from('integrations').select('*').eq('id', integrationId).single();
        if(refetchError || !integration) throw new Error('Could not refetch integration details during sync.');
        
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
    };

    try {
        await retry(syncOperation, {
            maxAttempts: 3,
            delayMs: 2000,
            onRetry: (error, attempt) => {
                logger.warn(`[Sync Service] Sync attempt ${attempt} failed for integration ${integrationId}: ${error.message}. Retrying...`);
            },
        });
    } catch (e: unknown) {
        logError(e, { context: `Sync failed permanently for integration ${integrationId}` });
        await supabase.from('integrations').update({ sync_status: 'failed' }).eq('id', integrationId);
        throw new Error(`Sync failed after multiple attempts. Please check the logs.`);
    }
}
