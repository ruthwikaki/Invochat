
'use server';
import { logger } from './logger';
import { cookies } from 'next/headers';
import crypto from 'crypto';

export const CSRF_COOKIE_NAME = '__Host-csrf_token';
export const CSRF_FORM_NAME = 'csrf_token';

/**
 * Generates a CSRF token using crypto.randomUUID() and sets it as a cookie.
 * This should be called from a Server Component or Route Handler that renders the form.
 */
export function generateCSRFToken(): void {
  const token = crypto.randomUUID();
  cookies().set({
    name: CSRF_COOKIE_NAME,
    value: token,
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    sameSite: 'strict',
  });
}

/**
 * Validates a CSRF token from a FormData object against the one stored in a cookie.
 * This function is designed to be called at the beginning of a server action.
 * @param formData The FormData object from the form submission.
 * @throws {Error} If the tokens are missing or do not match.
 */
export function validateCSRF(formData: FormData): void {
  const tokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
  const tokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;

  if (!tokenFromForm || !tokenFromCookie || tokenFromForm !== tokenFromCookie) {
    logger.warn(`[CSRF] Invalid token. Action rejected. Form: ${tokenFromForm}, Cookie: ${tokenFromCookie}`);
    throw new Error('Invalid form submission. Please refresh the page and try again.');
  }
}

/**
 * Reads a cookie value on the client-side.
 * This is a helper function for client components to get the CSRF token.
 * @param name The name of the cookie to read.
 * @returns The cookie value, or null if not found.
 */
export function getCookie(name: string): string | null {
    if (typeof document === 'undefined') {
        // This function is client-side only, return null on the server.
        return null;
    }
    const value = `; ${document.cookie}`;
    const parts = value.split(`; ${name}=`);
    if (parts.length === 2) return parts.pop()?.split(';').shift() || null;
    return null;
}
