
'use client';

import { CSRF_COOKIE_NAME } from './csrf';
import { Dispatch, SetStateAction } from 'react';

/**
 * Reads a cookie value on the client-side.
 * This is a helper function for client components to get the CSRF token.
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
 * A client-side helper to fetch and set a CSRF token.
 * This function is necessary because the token must be generated on the server
 * via a Server Action, and then read by the client.
 * @param setCsrfToken The state setter from a `useState` hook.
 */
export async function generateAndSetCsrfToken(setCsrfToken: Dispatch<SetStateAction<string | null>>) {
    try {
        const response = await fetch('/api/auth/csrf', { method: 'POST' });
        if (response.ok) {
            const token = getCookie(CSRF_COOKIE_NAME);
            setCsrfToken(token);
        }
    } catch (error) {
        console.error('Failed to generate CSRF token:', error);
    }
}
