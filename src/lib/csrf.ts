
'use server';

import { logger } from './logger';
import { cookies } from 'next/headers';
import crypto from 'crypto';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from './csrf-client';

/**
 * Generates a CSRF token using crypto.randomUUID() and sets it as a cookie.
 * This should be called from a Server Component or Route Handler that renders the form.
 * @returns The generated CSRF token.
 */
export async function generateCSRFToken(): Promise<string> {
  const token = crypto.randomUUID();
  cookies().set({
    name: CSRF_COOKIE_NAME,
    value: token,
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    sameSite: 'strict',
  });
  return token;
}

/**
 * Reads the CSRF token from the cookie.
 * This is useful for passing the token as a prop to a client component.
 */
export function getCSRFToken(): string | null {
    return cookies().get(CSRF_COOKIE_NAME)?.value || null;
}

/**
 * Validates a CSRF token from a FormData object against the one stored in a cookie.
 * This function is designed to be called at the beginning of a server action.
 * @param formData The FormData object from the form submission.
 * @throws {Error} If the tokens are missing or do not match.
 */
export async function validateCSRF(formData: FormData): Promise<void> {
  const tokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
  const tokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;

  if (!tokenFromForm || !tokenFromCookie || tokenFromForm !== tokenFromCookie) {
    logger.warn(`[CSRF] Invalid token. Action rejected. Form: ${tokenFromForm}, Cookie: ${tokenFromCookie}`);
    throw new Error('Invalid form submission. Please refresh the page and try again.');
  }
}
