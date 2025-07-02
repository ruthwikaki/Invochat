
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
 * Validates a CSRF token from a request against the one stored in a cookie.
 * @param tokenFromRequest The token from the form or a header.
 * @param tokenFromCookie The token from the csrf_token cookie.
 * @returns {boolean} True if the tokens are valid and match, false otherwise.
 */
export function validateCSRFToken(tokenFromRequest: string | null, tokenFromCookie: string | undefined): boolean {
  if (!tokenFromRequest || !tokenFromCookie || typeof tokenFromRequest !== 'string' || typeof tokenFromCookie !== 'string') {
    return false;
  }
  return tokenFromRequest === tokenFromCookie;
}
