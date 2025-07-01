
'use server';

import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';
import type { Platform } from '../types';

/**
 * Creates a new secret in Supabase Vault.
 * @param companyId The UUID of the company.
 * @param platform The integration platform (e.g., 'shopify').
 * @param secretValue The plaintext secret to store.
 * @returns The UUID of the newly created secret.
 */
export async function createVaultSecret(companyId: string, platform: Platform, secretValue: string): Promise<string> {
    const supabase = getServiceRoleClient();
    const secretName = `integration_token:${platform}:${companyId}`;
    
    logger.info(`[Vault] Creating new secret: ${secretName}`);

    const { data, error } = await supabase.vault.secrets.create({
        name: secretName,
        secret: secretValue,
        description: `API token for ${platform} integration for company ${companyId}`,
    });

    if (error) {
        logError(error, { context: `Failed to create Vault secret for ${platform} - ${companyId}` });
        throw new Error('Could not securely store integration credentials. Please ensure Supabase Vault is enabled for your project.');
    }

    return data.id;
}

/**
 * Retrieves a secret from Supabase Vault.
 * @param secretId The UUID of the secret to retrieve.
 * @returns The plaintext secret value.
 */
export async function retrieveVaultSecret(secretId: string): Promise<string> {
    const supabase = getServiceRoleClient();
    
    const { data, error } = await supabase.vault.secrets.get(secretId);

    if (error) {
        logError(error, { context: `Failed to retrieve Vault secret ID ${secretId}` });
        throw new Error('Could not retrieve integration credentials.');
    }

    if (!data.secret) {
        throw new Error(`Vault secret with ID ${secretId} found, but value is empty.`);
    }

    return data.secret;
}

/**
 * Updates an existing secret in Supabase Vault.
 * @param secretId The UUID of the secret to update.
 * @param newSecretValue The new plaintext value.
 */
export async function updateVaultSecret(secretId: string, newSecretValue: string): Promise<void> {
    const supabase = getServiceRoleClient();
    logger.info(`[Vault] Updating secret ID: ${secretId}`);

    const { error } = await supabase.vault.secrets.update(secretId, {
        secret: newSecretValue,
    });

    if (error) {
        logError(error, { context: `Failed to update Vault secret ID ${secretId}` });
        throw new Error('Could not update integration credentials.');
    }
}

/**
 * Deletes a secret from Supabase Vault.
 * This is irreversible.
 * @param secretId The UUID of the secret to delete.
 */
export async function deleteVaultSecret(secretId: string): Promise<void> {
    const supabase = getServiceRoleClient();
    logger.warn(`[Vault] Deleting secret ID: ${secretId}`);

    const { error } = await supabase.vault.secrets.delete(secretId);

    if (error) {
        // It's possible the secret was already deleted, so we don't want to throw a fatal error.
        // We'll log it as a warning instead.
        logger.warn(`[Vault] Could not delete Vault secret ID ${secretId}. It may have already been removed.`);
    }
}
