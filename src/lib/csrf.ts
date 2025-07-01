
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
 * Compares two strings in a way that protects against timing attacks.
 * This is a standard and safe implementation for this use case.
 * It's crucial for securely validating tokens without leaking information.
 * @param a The first string (e.g., from a form).
 * @param b The second string (e.g., from a cookie).
 * @returns True if the strings are identical, false otherwise.
 */
function timingSafeEqual(a: string, b: string): boolean {
  // Both strings must be of equal length.
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  // XOR each character code. If strings are identical, result will remain 0.
  // This loop always runs for the full length of the string, preventing an
  // attacker from guessing the token's content based on response time.
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }

  return result === 0;
}

/**
 * Validates a CSRF token from a form against the one stored in a cookie.
 * Uses a timing-safe comparison to prevent timing attacks.
 */
export function validateCSRFToken(tokenFromForm: string, tokenFromCookie: string): boolean {
  if (!tokenFromForm || !tokenFromCookie || typeof tokenFromForm !== 'string' || typeof tokenFromCookie !== 'string') {
    return false;
  }

  return timingSafeEqual(tokenFromForm, tokenFromCookie);
}
