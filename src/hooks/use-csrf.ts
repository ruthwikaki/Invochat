
'use client';
import { useState, useEffect } from 'react';
import { CSRF_COOKIE_NAME } from '@/lib/csrf';

// A simple, robust function to get a cookie by name from the browser.
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
 * It initializes its state synchronously from the cookie, which helps prevent
 * race conditions where components render before the token is available.
 */
export function useCsrfToken() {
  // Initialize state directly from the cookie if available.
  const [token, setToken] = useState<string | null>(() => getCookie(CSRF_COOKIE_NAME));

  useEffect(() => {
    // This effect serves as a fallback, for example if the cookie is set
    // after the initial component mount for some reason.
    if (!token) {
      const cookieToken = getCookie(CSRF_COOKIE_NAME);
      if (cookieToken) {
        setToken(cookieToken);
      }
    }
  }, [token]);

  return token;
}
