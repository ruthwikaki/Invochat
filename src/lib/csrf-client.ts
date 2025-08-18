
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
    try {
        logger.debug("Starting CSRF token generation...");
        const response = await fetch('/api/auth/csrf', { method: 'POST' });
        const result = await response.json();
        logger.debug("CSRF API response:", result);
        
        if (result.success) {
            // Give the cookie a moment to be set, then read it
            await new Promise(resolve => setTimeout(resolve, 100));
            const token = getCookie(CSRF_COOKIE_NAME);
            logger.debug("Retrieved CSRF token from cookie:", token ? "Token found" : "No token found");
            setCsrfToken(token);
            logger.debug("CSRF token set from cookie.");
        } else {
            logger.error("Failed to generate CSRF token:", result.error);
            setCsrfToken(null);
        }
    } catch (error) {
        logger.error("Error generating CSRF token:", error);
        setCsrfToken(null);
    }
}
