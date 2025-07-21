'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';

/**
 * Creates or updates a secret in Supabase Vault. This is the secure way to store
 * third-party credentials. Supabase handles the encryption and key management.
 * @param companyId The ID of the company the secret belongs to.
 * @param platform The platform the secret is for (e.g., 'shopify').
 * @param plaintextValue The raw, unencrypted credential to store.
 * @returns The ID of the created or updated secret.
 */
export async function createOrUpdateSecret(companyId: string, platform: string, plaintextValue: string): Promise<string> {
    const supabase = getServiceRoleClient();
    // Use a predictable naming convention for secrets to ensure one per integration.
    const secretName = `${platform}_token_${companyId}`;
    
    try {
        const { data: secret, error } = await (supabase as any).vault.secrets.create({
            name: secretName,
            secret: plaintextValue,
            description: `API token for ${platform} for company ${companyId}`,
        });
        
        if (error) {
            // If the secret already exists, Supabase throws a unique constraint error.
            if (error.message.includes('unique constraint')) {
                logger.info(`[Vault] Secret for ${secretName} already exists. Updating it instead.`);
                // Update the existing secret with the new value.
                const { data: updatedSecret, error: updateError } = await (supabase as any).vault.secrets.update(secretName, {
                    secret: plaintextValue,
                });
                if (updateError) {
                    throw new Error(`Failed to update existing secret: ${updateError.message}`);
                }
                logger.info(`[Vault] Successfully updated encrypted secret for ${secretName}.`);
                return updatedSecret.id;
            }
            throw new Error(`Failed to create secret: ${error.message}`);
        }
        
        logger.info(`[Vault] Successfully created encrypted secret for ${secretName}.`);
        return secret.id;
    } catch (e: unknown) {
        logError(e, { context: 'createOrUpdateSecret', companyId, platform });
        throw e;
    }
}

/**
 * Retrieves and decrypts a secret from Supabase Vault.
 * @param companyId The ID of the company.
 * @param platform The platform the secret is for.
 * @returns The decrypted secret value, or null if not found.
 */
export async function getSecret(companyId: string, platform: string): Promise<string | null> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;

    try {
        const { data, error } = await (supabase as any).vault.secrets.retrieve(secretName);
        
        if (error) {
            // A 404 error is expected if the secret doesn't exist yet.
            if (error.message.includes('404')) {
                logger.warn(`[Vault] Secret not found for ${secretName}`);
                return null;
            }
            throw new Error(`Failed to retrieve secret: ${error.message}`);
        }
        
        if (!data.secret) {
            logger.warn(`[Vault] Secret for ${secretName} was found but is empty.`);
            return null;
        }
        
        // Supabase Vault automatically handles decryption when retrieving the secret.
        return data.secret;
    } catch (e: unknown) {
        logError(e, { context: 'getSecret', companyId, platform });
        throw e;
    }
}
