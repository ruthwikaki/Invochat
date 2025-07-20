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

  const { data: { session } } = await supabase.auth.getSession();
  const user = session?.user;
  const { pathname } = req.nextUrl;

  const publicRoutes = ['/', '/login', '/signup', '/forgot-password', '/update-password', '/database-setup', '/env-check'];
  
  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));

  // If the user is not authenticated and the route is not public, redirect to login
  if (!user && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }
  
  if (user) {
    // If the user is logged in, but their company setup is not complete, force them to the setup page
    if (!user.app_metadata.company_id && !pathname.startsWith('/env-check')) {
       return NextResponse.redirect(new URL('/env-check', req.url));
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