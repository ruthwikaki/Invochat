
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

  // This line is crucial. It forces the session to be refreshed from the cookies.
  const { data: { user } } = await supabase.auth.getUser();

  // Define public routes that do not require authentication
  const publicRoutes = ['/login', '/signup', '/forgot-password', '/update-password', '/database-setup', '/env-check'];
  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));
  const isLandingPage = pathname === '/';
  
  // If the user is logged in
  if (user) {
    // If user has no company_id, redirect them to the setup page.
    if (!user.app_metadata.company_id && pathname !== '/env-check') {
        return NextResponse.redirect(new URL('/env-check', req.url));
    }

    // If company is set up and they are on a public-only route, redirect to dashboard.
    if (isPublicRoute && user.app_metadata.company_id) {
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
