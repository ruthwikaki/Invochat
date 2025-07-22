
import { generateCSRFToken } from '@/lib/csrf';
import { NextResponse } from 'next/server';

/**
 * An API route to explicitly generate a CSRF token and set it in a cookie.
 * Client components can call this route to ensure they have a valid CSRF token
 * before submitting a form that uses a Server Action for authentication.
 */
export async function POST() {
  try {
    generateCSRFToken();
    return NextResponse.json({ success: true }, { status: 200 });
  } catch (e) {
    return NextResponse.json({ success: false, error: 'Failed to generate CSRF token.' }, { status: 500 });
  }
}
