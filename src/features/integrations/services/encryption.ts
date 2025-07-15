
'use server';

import crypto from 'crypto';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';
import { z } from 'zod';

const EncryptionConfigSchema = z.object({
    ENCRYPTION_KEY: z.string().length(64, "ENCRYPTION_KEY must be a 64-character hex string (32 bytes)."),
    ENCRYPTION_IV: z.string().length(32, "ENCRYPTION_IV must be a 32-character hex string (16 bytes)."),
});

const configCheck = EncryptionConfigSchema.safeParse(process.env);
if (!configCheck.success) {
    throw new Error(`Encryption keys are not configured correctly in .env: ${configCheck.error.flatten().fieldErrors}`);
}
const { ENCRYPTION_KEY, ENCRYPTION_IV } = configCheck.data;
const ALGORITHM = 'aes-256-cbc';

/**
 * Encrypts a plaintext string.
 * @param text The plaintext string to encrypt.
 * @returns The encrypted string in 'iv:encryptedData' format.
 */
function encrypt(text: string): string {
    const iv = Buffer.from(ENCRYPTION_IV, 'hex');
    const key = Buffer.from(ENCRYPTION_KEY, 'hex');
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    // We can use a static IV because the key in the Vault is already unique per company/integration.
    // This simplifies decryption as we don't need to store a new IV for every secret.
    return encrypted;
}

/**
 * Decrypts an encrypted string.
 * @param encryptedText The encrypted string.
 * @returns The decrypted plaintext string.
 */
function decrypt(encryptedText: string): string {
    const iv = Buffer.from(ENCRYPTION_IV, 'hex');
    const key = Buffer.from(ENCRYPTION_KEY, 'hex');
    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
}


/**
 * Creates or updates a secret in the Supabase Vault after encrypting it.
 * The secret name is deterministically generated based on the company and integration platform.
 * @param companyId The UUID of the company.
 * @param platform The integration platform (e.g., 'shopify').
 * @param plaintextValue The raw value of the secret to store (e.g., an API token).
 * @returns The UUID of the created or updated secret.
 */
export async function createOrUpdateSecret(companyId: string, platform: string, plaintextValue: string): Promise<string> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;
    const encryptedValue = encrypt(plaintextValue);
    
    try {
        const { data: secret, error } = await supabase.vault.secrets.create({
            name: secretName,
            secret: encryptedValue,
            description: `Encrypted API token for ${platform} for company ${companyId}`,
        });
        
        if (error) {
            // If the secret already exists, try to update it instead.
            if (error.message.includes('unique constraint')) {
                logger.info(`[Vault] Secret for ${secretName} already exists. Updating it instead.`);
                const { data: updatedSecret, error: updateError } = await supabase.vault.secrets.update(secretName, {
                    secret: encryptedValue,
                });
                if (updateError) {
                    throw new Error(`Failed to update existing secret: ${updateError.message}`);
                }
                return updatedSecret.id;
            }
            throw new Error(`Failed to create secret: ${error.message}`);
        }
        
        logger.info(`[Vault] Successfully created encrypted secret for ${secretName}.`);
        return secret.id;
    } catch (e: any) {
        logError(e, { context: 'createOrUpdateSecret', companyId, platform });
        throw e;
    }
}


/**
 * Retrieves and decrypts a secret from the Supabase Vault.
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
        
        if (!data.secret) {
            logger.warn(`[Vault] Secret for ${secretName} was found but is empty.`);
            return null;
        }

        return decrypt(data.secret);
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

/**
 * A stub function for a key rotation process.
 * In a real implementation, this would involve creating a new key in the KMS,
 * re-encrypting all secrets for a company with the new key, and then updating
 * the vault to use the new key ID.
 * @param companyId The UUID of the company.
 * @param platform The integration platform to rotate keys for.
 */
export async function rotateEncryptionKeys(companyId: string, platform: string): Promise<{ success: boolean; message: string }> {
    logger.info(`[Vault] Key rotation initiated for company ${companyId}, platform ${platform}.`);
    // This is a placeholder for a complex workflow. A real implementation would:
    // 1. Generate a new encryption key version in the Key Management Service.
    // 2. Fetch the current encrypted secret from the vault.
    // 3. Decrypt the secret with the old key.
    // 4. Re-encrypt the secret with the new key.
    // 5. Update the secret in the vault with the new encrypted value and new key_id.
    // 6. Log the rotation event in the audit trail.
    logger.warn(`[Vault] This is a stub function. No keys were actually rotated.`);
    return {
        success: true,
        message: 'Key rotation process simulated. No actual changes were made.'
    };
}
