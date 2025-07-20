
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

  const authRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  const isAuthRoute = authRoutes.some(route => pathname.startsWith(route));
  const isProtectedRoute = !isAuthRoute && pathname !== '/';

  if (!user && isProtectedRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }
  
  if (user) {
    if (!user.app_metadata.company_id && pathname !== '/env-check') {
       return NextResponse.redirect(new URL('/env-check', req.url));
    }
    if (isAuthRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
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
