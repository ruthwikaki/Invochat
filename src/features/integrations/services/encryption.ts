
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

function encrypt(text: string): string {
    const iv = Buffer.from(ENCRYPTION_IV, 'hex');
    const key = Buffer.from(ENCRYPTION_KEY, 'hex');
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return encrypted;
}

function decrypt(encryptedText: string): string {
    const iv = Buffer.from(ENCRYPTION_IV, 'hex');
    const key = Buffer.from(ENCRYPTION_KEY, 'hex');
    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
}


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

export async function getSecret(companyId: string, platform: string): Promise<string | null> {
    const supabase = getServiceRoleClient();
    const secretName = `${platform}_token_${companyId}`;

    try {
        const { data, error } = await supabase.vault.secrets.retrieve(secretName);
        
        if (error) {
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
