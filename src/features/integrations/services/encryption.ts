
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';

/**
 * Creates or updates a secret in the Supabase Vault.
 * The secret name is deterministically generated based on the company and integration platform.
 * @param companyId The UUID of the company.
 * @param platform The integration platform (e.g., 'shopify').
 * @param plaintextValue The raw value of the secret to store (e.g., an API token).
 * @returns The UUID of the created or updated secret.
 */
export async function createOrUpdateSecret(companyId: string, platform: string, plaintextValue: string): Promise<string> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;
    
    try {
        const { data: secret, error } = await supabase.vault.secrets.create({
            name: secretName,
            secret: plaintextValue,
            description: `API token for ${platform} integration for company ${companyId}`,
        });
        
        if (error) {
            // If the secret already exists, try to update it instead.
            if (error.message.includes('unique constraint')) {
                logger.info(`[Vault] Secret for ${secretName} already exists. Updating it instead.`);
                const { data: updatedSecret, error: updateError } = await supabase.vault.secrets.update(secretName, {
                    secret: plaintextValue,
                });
                if (updateError) {
                    throw new Error(`Failed to update existing secret: ${updateError.message}`);
                }
                return updatedSecret.id;
            }
            throw new Error(`Failed to create secret: ${error.message}`);
        }
        
        logger.info(`[Vault] Successfully created secret for ${secretName}.`);
        return secret.id;
    } catch (e: any) {
        logError(e, { context: 'createOrUpdateSecret', companyId, platform });
        throw e;
    }
}


/**
 * Retrieves a secret from the Supabase Vault.
 * @param companyId The UUID of the company.
 * @param platform The integration platform.
 * @returns The plaintext secret value, or null if not found.
 */
export async function getSecret(companyId: string, platform: string): Promise<string | null> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;

    try {
        const { data, error } = await supabase.vault.secrets.retrieve(secretName);
        
        if (error) {
            // A 404 error is expected if the secret doesn't exist, so we handle it gracefully.
            if (error.message.includes('404')) {
                logger.warn(`[Vault] Secret not found for ${secretName}`);
                return null;
            }
            throw new Error(`Failed to retrieve secret: ${error.message}`);
        }
        
        return data.secret;
    } catch (e: any) {
        logError(e, { context: 'getSecret', companyId, platform });
        throw e;
    }
}

/**
 * Deletes a secret from the Supabase Vault.
 * @param companyId The UUID of the company.
 * @param platform The integration platform.
 */
export async function deleteSecret(companyId: string, platform: string): Promise<void> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;
    
    try {
        const { error } = await supabase.vault.secrets.delete(secretName);
        
        if (error && !error.message.includes('404')) {
            throw new Error(`Failed to delete secret: ${error.message}`);
        }
        
        logger.info(`[Vault] Successfully deleted secret for ${secretName}.`);
    } catch (e: any) {
        logError(e, { context: 'deleteSecret', companyId, platform });
        throw e;
    }
}
