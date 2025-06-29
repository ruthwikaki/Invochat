
'use server';
import crypto from 'crypto';

export const CSRF_COOKIE_NAME = 'csrf_token';
export const CSRF_FORM_NAME = 'csrf_token';

export function generateCSRFToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function validateCSRFToken(tokenFromForm: string, tokenFromCookie: string): boolean {
  if (!tokenFromForm || !tokenFromCookie || typeof tokenFromForm !== 'string' || typeof tokenFromCookie !== 'string') {
    return false;
  }

  try {
    const formBuffer = Buffer.from(tokenFromForm, 'hex');
    const cookieBuffer = Buffer.from(tokenFromCookie, 'hex');

    if (formBuffer.length !== cookieBuffer.length) {
      return false;
    }

    return crypto.timingSafeEqual(formBuffer, cookieBuffer);
  } catch (error) {
    // If Buffer.from fails (e.g., invalid hex string), it's a bad token.
    return false;
  }
}
