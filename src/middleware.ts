
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { logger } from './lib/logger';
import { generateCSRFToken, CSRF_COOKIE_NAME } from './lib/csrf';

export async function middleware(req: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // The official pattern is to update request and response cookies
          req.cookies.set({ name, value, ...options });
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          req.cookies.set({ name, value: '', ...options });
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // This call refreshes the session and mutates `response` via the cookie handlers
  const { data: { user } } = await supabase.auth.getUser();

  // --- Start CSRF Cookie Handling ---
  if (!req.cookies.has(CSRF_COOKIE_NAME)) {
    const csrfToken = generateCSRFToken();
    response.cookies.set({
      name: CSRF_COOKIE_NAME,
      value: csrfToken,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      httpOnly: false,
      path: '/',
    });
  }
  // --- End CSRF Cookie Handling ---

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  // The /env-check route has been removed from public access to prevent information exposure.
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);
  
  // --- Start Redirect Logic ---
  if (user) {
    if (pathname === '/update-password' && req.nextUrl.searchParams.has('code')) {
      // Allow password reset even when logged in
      return response;
    }
    if (isAuthRoute) {
      // User is logged in and tries to access auth page -> redirect to chat
      return NextResponse.redirect(new URL('/chat', req.url));
    }
    if (pathname === '/') {
      return NextResponse.redirect(new URL('/chat', req.url));
    }

    const companyId = user.app_metadata?.company_id || user.user_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';
    
    // User is logged in but company setup is incomplete
    if (!companyId && !isSetupIncompleteRoute && !isPublicRoute && pathname !== '/test-supabase') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
    }
    
    // User has completed setup but is trying to access the setup page
    if (companyId && isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/chat', req.url));
    }

  } else {
    // User is not logged in
    if (!isAuthRoute && !isPublicRoute && pathname !== '/update-password') {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  // --- End Redirect Logic ---

  // For all allowed paths, return the response (which now has session and CSRF cookies)
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public|api).*)'],
};
