
import { _generateCSRFToken } from '@/lib/csrf';
import { NextResponse } from 'next/server';

/**
 * An API route to explicitly generate a CSRF token and set it in a cookie.
 * Client components can call this route to ensure they have a valid CSRF token
 * before submitting a form that uses a Server Action for authentication.
 * 
 * THIS IS CURRENTLY NOT USED as we rely on Supabase's built-in session handling.
 * It is kept for reference for stateful session patterns.
 */
export async function POST() {
  try {
    // await _generateCSRFToken(); // Temporarily disabled
    return NextResponse.json({ success: true, message: "CSRF handling is currently managed by Supabase session cookies." }, { status: 200 });
  } catch (e) {
    return NextResponse.json({ success: false, error: 'Failed to generate CSRF token.' }, { status: 500 });
  }
}

