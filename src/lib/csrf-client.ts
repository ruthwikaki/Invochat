
'use client';

import type { Dispatch, SetStateAction } from 'react';
import { logger } from './logger';

export const CSRF_COOKIE_NAME = 'csrf_token';
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
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
}

/**
 * A client-side helper to fetch a CSRF token from a dedicated API route.
 * @param setCsrfToken The state setter from a `useState` hook to store the token.
 */
export async function generateAndSetCsrfToken(setCsrfToken: Dispatch<SetStateAction<string | null>>) {
    // This functionality is currently disabled in favor of Supabase's built-in session handling.
    // Kept for reference.
    logger.debug("CSRF token generation via API call is disabled.");
    setCsrfToken("dummy-token-for-now"); // Set a dummy token to enable form submission
}
