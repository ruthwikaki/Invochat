
'use server';

import { cookies } from 'next/headers';
import crypto from 'crypto';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from './csrf-client';

const CSRF_TOKEN_MAX_AGE_SECONDS = 60 * 60; // 1 hour

/**
 * Generates a CSRF token using crypto.randomUUID() and sets it as a cookie.
 * This should be called from a Server Component or Route Handler that renders the form.
 * @returns The generated CSRF token.
 */
export async function generateCSRFToken(): Promise<string> {
  const token = crypto.randomUUID();
  const expires = new Date(Date.now() + CSRF_TOKEN_MAX_AGE_SECONDS * 1000);
  
  cookies().set({
    name: CSRF_COOKIE_NAME,
    value: token,
    httpOnly: false, // Allow JavaScript to read this cookie
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    sameSite: 'strict',
    expires: expires,
    maxAge: CSRF_TOKEN_MAX_AGE_SECONDS,
  });
  return token;
}

/**
 * Reads the CSRF token from the cookie.
 * This is useful for passing the token as a prop to a client component.
 */
export async function getCSRFToken(): Promise<string | null> {
    return cookies().get(CSRF_COOKIE_NAME)?.value || null;
}

/**
 * Validates a CSRF token from a FormData object against the one stored in a cookie.
 * This function is designed to be called at the beginning of a server action.
 * @param formData The FormData object from the form submission.
 * @throws {Error} If the tokens are missing or do not match.
 */
export async function validateCSRF(formData: FormData): Promise<void> {
  const token = formData.get(CSRF_FORM_NAME) as string;
  const cookieToken = await getCSRFToken();
  
  if (!token || !cookieToken || token !== cookieToken) {
    throw new Error('Invalid CSRF token');
  }
}
