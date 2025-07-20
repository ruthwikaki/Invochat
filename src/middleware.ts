
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

  if (!supabaseUrl || !supabaseAnonKey) {
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
          response.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();
  const { pathname } = req.nextUrl;

  const publicRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  const setupRoutes = ['/database-setup', '/env-check'];
  
  const isPublicRoute = publicRoutes.includes(pathname);
  const isAuthRoute = pathname.startsWith('/login') || pathname.startsWith('/signup');
  const isLandingPage = pathname === '/';

  // Allow access to setup routes regardless of auth state
  if (setupRoutes.includes(pathname)) {
    return response;
  }

  if (user) {
    // If the user IS logged in but doesn't have a company_id, they need to run the setup script.
    if (!user.app_metadata.company_id && pathname !== '/env-check') {
        return NextResponse.redirect(new URL('/env-check', req.url));
    }
    // If user is logged in and tries to access login/signup, redirect to app root
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/', req.url));
    }
  } else {
    // If user is not logged in, allow access to landing page.
    // For all other routes, redirect to login.
    if (!isLandingPage && !isPublicRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - api/ (API routes which have their own auth)
     */
    '/((?!_next/static|_next/image|favicon.ico|api/).*)',
  ],
}
