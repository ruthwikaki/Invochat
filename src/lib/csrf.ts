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
 * @param tokenFromCookie The value of the CSRF token from the user's cookie.
 * @throws {Error} If the tokens are missing or do not match.
 */
export function validateCSRF(formData: FormData, tokenFromCookie: string | undefined): void {
  const tokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;

  if (!tokenFromForm || !tokenFromCookie || tokenFromForm !== tokenFromCookie) {
    logger.warn(`[CSRF] Invalid token. Action rejected. Form: ${tokenFromForm}, Cookie: ${tokenFromCookie}`);
    throw new Error('Invalid form submission. Please refresh the page and try again.');
  }
}

/**
 * Reads a cookie value on the client-side.
 * @param name The name of the cookie to read.
 * @returns The cookie value, or null if not found.
 */
export function getCookie(name: string): string | null {
    if (typeof document === 'undefined') {
        // This function is client-side only
        return null;
    }
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop()?.split(';').shift() || null;
    return null;
}
