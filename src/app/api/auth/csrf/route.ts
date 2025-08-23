

import { generateCSRFToken } from '@/lib/csrf';
import { NextResponse } from 'next/server';

/**
 * An API route to explicitly generate a CSRF token and set it in a cookie.
 * Client components can call this route to ensure they have a valid CSRF token
 * before submitting a form that uses a Server Action for authentication.
 */
export async function POST() {
  try {
    await generateCSRFToken();
    return NextResponse.json({ success: true, message: "CSRF token set successfully." }, { status: 200 });
  } catch (error) {
    console.error('CSRF generation failed:', error);
    return NextResponse.json({ success: false, error: 'Failed to generate CSRF token.' }, { status: 500 });
  }
}
