
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

  const { data: { session } } = await supabase.auth.getSession();
  const user = session?.user;

  // Define public routes that do not require authentication
  const publicRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));
  
  // If the user is logged in
  if (user) {
    // If user has no company_id, they must complete setup
    if (!user.app_metadata.company_id && !pathname.startsWith('/env-check')) {
        return NextResponse.redirect(new URL('/env-check', req.url));
    }

    // If company is set up and they are on a public-only route, redirect to dashboard.
    if (isPublicRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } 
  // If the user is not logged in
  else {
    // Allow access to landing page, but redirect other root access to login
    if (pathname === '/') {
        return NextResponse.next();
    }
    // If the user is trying to access a protected route, redirect them to the login page.
    const isProtectedRoute = !isPublicRoute && !pathname.startsWith('/auth/callback') && !pathname.startsWith('/env-check') && !pathname.startsWith('/database-setup');
    if (isProtectedRoute) {
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
     * - api/ (API routes have their own auth)
     */
    '/((?!_next/static|_next/image|favicon.ico|api/).*)',
  ],
}
