
'use client';

import { useState, useEffect } from 'react';
import { CSRF_COOKIE_NAME } from '@/lib/csrf';

/**
 * A simple, robust function to get a cookie by name from the browser.
 * This function should only be called on the client side.
 * @param name The name of the cookie to retrieve.
 * @returns The cookie value, or null if not found.
 */
function getCookie(name: string): string | null {
  if (typeof document === 'undefined') {
    return null;
  }
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) {
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
}

/**
 * A client-side hook to get the CSRF token.
 * It waits for the component to mount on the client, then reads the
 * security token from the cookie once, ensuring reliability.
 */
export function useCsrfToken() {
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    // This effect runs only once on the client, after the component has mounted.
    // This is the correct and safe way to access browser-specific APIs like `document.cookie`.
    setToken(getCookie(CSRF_COOKIE_NAME));
  }, []); // The empty dependency array `[]` ensures this effect runs only once.

  return token;
}
