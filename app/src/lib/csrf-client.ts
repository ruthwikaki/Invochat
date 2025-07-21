
'use client';

export const CSRF_COOKIE_NAME = '__Host-csrf_token';
export const CSRF_FORM_NAME = 'csrf_token';

/**
 * Reads a cookie value on the client-side.
 * @param name The name of the cookie to read.
 * @returns The cookie value, or null if not found.
 */
export function getCookie(name: string): string | null {
    if (typeof document === 'undefined') {
        return null;
    }
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) {
      const popped = parts.pop();
      return popped ? popped.split(';').shift() || null : null;
    }
    return null;
}

