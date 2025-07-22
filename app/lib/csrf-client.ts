'use client';

import { Dispatch, SetStateAction } from 'react';
import { logger } from './logger';

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
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
}

/**
 * A client-side helper to fetch a CSRF token from a dedicated API route.
 * @param setCsrfToken The state setter from a `useState` hook to store the token.
 */
export async function generateAndSetCsrfToken(setCsrfToken: Dispatch<SetStateAction<string | null>>) {
    try {
        const response = await fetch('/api/auth/csrf', { method: 'POST' });
        if (response.ok) {
            const token = getCookie(CSRF_COOKIE_NAME);
            setCsrfToken(token);
        } else {
            logger.error('Failed to fetch CSRF token from API.', { status: response.status });
        }
    } catch (error) {
        logger.error('Error fetching CSRF token:', error);
    }
}