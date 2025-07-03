

'use server';

import { cookies } from 'next/headers';
import { logger } from './logger';

export const CSRF_COOKIE_NAME = 'csrf_token';
export const CSRF_FORM_NAME = 'csrf_token';

/**
 * Generates a CSRF token using the global crypto.randomUUID(),
 * which is available in both Node.js and Edge runtimes.
 */
export function generateCSRFToken(): string {
  return crypto.randomUUID();
}

/**
 * Validates a CSRF token from a FormData object against the one stored in a cookie.
 * This function is designed to be called at the beginning of a server action.
 * @param formData The FormData object from the form submission.
 * @throws {Error} If the tokens are missing or do not match.
 */
export function validateCSRF(formData: FormData): void {
  const tokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;
  const tokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;

  if (!tokenFromForm || !tokenFromCookie || tokenFromForm !== tokenFromCookie) {
    logger.warn(`[CSRF] Invalid token. Action rejected. Form: ${tokenFromForm}, Cookie: ${tokenFromCookie}`);
    throw new Error('Invalid form submission. Please refresh the page and try again.');
  }
}
