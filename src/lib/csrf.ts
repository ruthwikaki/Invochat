
// The crypto module was previously imported here for Jest compatibility, but it caused
// a runtime error in the Next.js Edge Runtime. We now rely on the globally available
// 'crypto' object, which is present in both modern Node.js and Edge environments.

export const CSRF_COOKIE_NAME = 'csrf_token';
export const CSRF_FORM_NAME = 'csrf_token';

/**
 * Generates a CSRF token using the global crypto.randomUUID(),
 * which is available in both Node.js and Edge runtimes.
 */
export function generateCSRFToken(): string {
  // This uses the Web Crypto API's randomUUID, available globally.
  return crypto.randomUUID();
}

/**
 * Validates a CSRF token from a form against the one stored in a cookie.
 * Uses a timing-safe comparison to prevent timing attacks.
 * @param tokenFromForm The token from the form input.
 * @param tokenFromCookie The token from the cookie.
 * @returns {boolean} True if the tokens are valid and match, false otherwise.
 */
export function validateCSRFToken(tokenFromForm: string, tokenFromCookie: string): boolean {
  if (!tokenFromForm || !tokenFromCookie || typeof tokenFromForm !== 'string' || typeof tokenFromCookie !== 'string') {
    return false;
  }
  return tokenFromForm === tokenFromCookie;
}
