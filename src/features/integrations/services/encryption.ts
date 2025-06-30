
'use server';

import crypto from 'crypto';
import { config } from '@/config/app-config';

const ALGORITHM = 'aes-256-cbc';

/**
 * A helper function to get the encryption key and IV from the configuration.
 * It throws a clear, user-friendly error if the keys are not set, preventing
 * the use of integrations until they are properly configured.
 */
function getCryptoDependencies() {
    const key = config.encryption.key;
    const iv = config.encryption.iv;

    if (!key || !iv) {
        throw new Error('Encryption keys are not configured in the .env file. Please set ENCRYPTION_KEY and ENCRYPTION_IV to use integrations.');
    }

    const encryptionKeyBuffer = Buffer.from(key, 'hex');
    const ivBuffer = Buffer.from(iv, 'hex');

    if (encryptionKeyBuffer.length !== 32) {
        throw new Error('Invalid encryption key length. Must be 32 bytes (64 hex characters).');
    }
    if (ivBuffer.length !== 16) {
        throw new Error('Invalid IV length. Must be 16 bytes (32 hex characters).');
    }

    return { encryptionKeyBuffer, ivBuffer };
}


/**
 * Encrypts a string using AES-256-CBC.
 * @param text The plaintext string to encrypt.
 * @returns A string containing the encrypted data in hex format.
 */
export function encrypt(text: string): string {
  const { encryptionKeyBuffer, ivBuffer } = getCryptoDependencies();
  const cipher = crypto.createCipheriv(ALGORITHM, encryptionKeyBuffer, ivBuffer);
  let encrypted = cipher.update(text, 'utf8', 'hex');
  encrypted += cipher.final('hex');
  return encrypted;
}

/**
 * Decrypts a string that was encrypted with the `encrypt` function.
 * @param encryptedText The hex-encoded encrypted string.
 * @returns The original plaintext string.
 */
export function decrypt(encryptedText: string): string {
  const { encryptionKeyBuffer, ivBuffer } = getCryptoDependencies();
  const decipher = crypto.createDecipheriv(ALGORITHM, encryptionKeyBuffer, ivBuffer);
  let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}
