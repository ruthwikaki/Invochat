
'use server';

import crypto from 'crypto';
import { config } from '@/config/app-config';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { logError } from '@/lib/error-handler';
import { logger } from '@/lib/logger';

const ALGORITHM = 'aes-256-cbc';

// --- Core Encryption Functions ---

/**
 * Encrypts text using a given key and IV.
 * @param text The plaintext to encrypt.
 * @param keyHex The encryption key as a 64-character hex string.
 * @param ivHex The initialization vector as a 32-character hex string.
 * @returns The encrypted data as a hex string, prefixed with the IV.
 */
function encryptWithKey(text: string, keyHex: string, ivHex: string): string {
    const key = Buffer.from(keyHex, 'hex');
    const iv = Buffer.from(ivHex, 'hex');
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    return encrypted;
}

/**
 * Decrypts text using a given key and IV.
 * @param encryptedHex The encrypted hex string.
 * @param keyHex The encryption key as a 64-character hex string.
 * @param ivHex The initialization vector as a 32-character hex string.
 * @returns The decrypted plaintext.
 */
function decryptWithKey(encryptedHex: string, keyHex: string, ivHex: string): string {
    const key = Buffer.from(keyHex, 'hex');
    const iv = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    let decrypted = decipher.update(encryptedHex, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
}

// --- Per-Company Key Management ---

type CompanyKeys = {
    key: string; // Plaintext hex key
    iv: string; // Plaintext hex IV
};

/**
 * Retrieves the encryption key and IV for a specific company.
 * If they don't exist, it generates new ones, saves them securely, and returns them.
 * @param companyId The UUID of the company.
 * @returns A promise resolving to the company's plaintext key and IV.
 */
async function getCompanyKeys(companyId: string): Promise<CompanyKeys> {
    const supabase = getServiceRoleClient();
    const masterKey = config.encryption.key;
    const masterIv = config.encryption.iv;

    const { data, error } = await supabase
        .from('company_secrets')
        .select('encrypted_key, encrypted_iv')
        .eq('company_id', companyId)
        .single();
    
    if (error && error.code !== 'PGRST116') { // 'PGRST116' means no rows found
        logError(error, { context: `Failed to fetch secrets for company ${companyId}` });
        throw new Error('Could not retrieve company encryption keys.');
    }

    if (data) {
        // Keys exist, decrypt them with the master key
        const companyKey = decryptWithKey(data.encrypted_key, masterKey, masterIv);
        const companyIv = decryptWithKey(data.encrypted_iv, masterKey, masterIv);
        return { key: companyKey, iv: companyIv };
    }

    // No keys found, so generate, encrypt, and store new ones
    logger.info(`[Encryption] No keys found for company ${companyId}. Generating new keys.`);
    const newCompanyKey = crypto.randomBytes(32).toString('hex');
    const newCompanyIv = crypto.randomBytes(16).toString('hex');

    const encryptedCompanyKey = encryptWithKey(newCompanyKey, masterKey, masterIv);
    const encryptedCompanyIv = encryptWithKey(newCompanyIv, masterKey, masterIv);

    const { error: insertError } = await supabase
        .from('company_secrets')
        .insert({
            company_id: companyId,
            encrypted_key: encryptedCompanyKey,
            encrypted_iv: encryptedCompanyIv,
        });
    
    if (insertError) {
        logError(insertError, { context: `Failed to insert new secrets for company ${companyId}` });
        throw new Error('Could not save new company encryption keys.');
    }

    // Return the new plaintext keys for immediate use
    return { key: newCompanyKey, iv: newCompanyIv };
}

// --- Public API ---

/**
 * Encrypts a string using the specific keys for a given company.
 * @param companyId The UUID of the company.
 * @param plaintext The text to encrypt.
 * @returns The encrypted hex string.
 */
export async function encryptForCompany(companyId: string, plaintext: string): Promise<string> {
    const { key, iv } = await getCompanyKeys(companyId);
    return encryptWithKey(plaintext, key, iv);
}

/**
 * Decrypts a string using the specific keys for a given company.
 * @param companyId The UUID of the company.
 * @param encryptedText The encrypted hex string.
 * @returns The decrypted plaintext.
 */
export async function decryptForCompany(companyId: string, encryptedText: string): Promise<string> {
    const { key, iv } = await getCompanyKeys(companyId);
    return decryptWithKey(encryptedText, key, iv);
}
