

export const CSRF_COOKIE_NAME = 'csrf_token';
export const CSRF_HEADER_NAME = 'x-csrf-token';

/**
 * Generates a CSRF token using the global crypto.randomUUID(),
 * which is available in both Node.js and Edge runtimes.
 */
export function generateCSRFToken(): string {
  return crypto.randomUUID();
}

/**
 * Validates a CSRF token from a request header against the one stored in a cookie.
 * This is a simple but effective way to protect against CSRF attacks.
 * @param tokenFromHeader The token from the X-CSRF-Token header.
 * @param tokenFromCookie The token from the csrf_token cookie.
 * @returns {boolean} True if the tokens are valid and match, false otherwise.
 */
export function validateCSRFToken(tokenFromHeader: string | null, tokenFromCookie: string | undefined): boolean {
  if (!tokenFromHeader || !tokenFromCookie || typeof tokenFromHeader !== 'string' || typeof tokenFromCookie !== 'string') {
    return false;
  }
  return tokenFromHeader === tokenFromCookie;
}
