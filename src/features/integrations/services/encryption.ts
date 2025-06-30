
'use server';

import crypto from 'crypto';
import { config } from '@/config/app-config';

const ALGORITHM = 'aes-256-cbc';
const ENCRYPTION_KEY = Buffer.from(config.encryption.key, 'hex'); // Must be 32 bytes (64 hex characters)
const IV = Buffer.from(config.encryption.iv, 'hex'); // Must be 16 bytes (32 hex characters)

if (ENCRYPTION_KEY.length !== 32) {
  throw new Error('Invalid encryption key length. Must be 32 bytes.');
}
if (IV.length !== 16) {
    throw new Error('Invalid IV length. Must be 16 bytes.');
}

/**
 * Encrypts a string using AES-256-CBC.
 * @param text The plaintext string to encrypt.
 * @returns A string containing the IV and the encrypted data, separated by a colon, in hex format.
 */
export function encrypt(text: string): string {
  const cipher = crypto.createCipheriv(ALGORITHM, ENCRYPTION_KEY, IV);
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
  const decipher = crypto.createDecipheriv(ALGORITHM, ENCRYPTION_KEY, IV);
  let decrypted = decipher.update(encryptedText, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}
