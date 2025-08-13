import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  
  const { pathname } = req.nextUrl;

  // Middleware should not run on static assets or API routes.
  if (pathname.startsWith('/_next') || pathname.startsWith('/api/') || pathname.startsWith('/static') || pathname.endsWith('.ico') || pathname.endsWith('.png')) {
    return response;
  }

  if (!supabaseUrl || !supabaseAnonKey) {
    // This is a server-side log, safe to use.
    console.warn("Supabase environment variables are not set. Middleware is bypassing auth checks.");
    return response;
  }

  const supabase = createServerClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
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
          response.cookies.delete({ name, ...options });
        },
      },
    }
  );

  // This function will refresh the session if expired.
  const { data: { session } } = await supabase.auth.getSession();

  // Define public routes that do not require authentication
  const publicRoutes = ['/login', '/signup', '/forgot-password', '/update-password', '/database-setup', '/env-check'];
  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));
  const isLandingPage = pathname === '/';
  
  // If the user is logged in
  if (session) {
    // If user has a session but they are on a public-only route or the landing page, redirect to dashboard.
    if (isPublicRoute || isLandingPage) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } 
  // If the user is not logged in
  else {
    // Allow access to the landing page and other public routes, but protect all other non-public routes.
    if (!isPublicRoute && !isLandingPage) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  
  // Add Security Headers
  response.headers.set('X-Frame-Options', 'DENY');
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('X-XSS-Protection', '1; mode=block');
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  
  // A basic Content-Security-Policy. This should be configured more specifically for your app's needs.
  response.headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://placehold.co;");


  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - api/ (API routes have their own auth logic)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - sentry-test/ (Sentry test route)
     */
    '/((?!api|_next/static|_next/image|favicon.ico|sentry-test).*)',
  ],
}
