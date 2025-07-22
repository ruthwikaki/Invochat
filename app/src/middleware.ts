
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
    // This case is handled by the root layout, but as a safeguard:
    return NextResponse.next();
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

  // Define routes that are only accessible to unauthenticated users
  const authRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];

  // Define fully public routes
  const publicRoutes = ['/'];

  const isAuthRoute = authRoutes.some(route => pathname.startsWith(route));
  const isPublicRoute = publicRoutes.includes(pathname);
  const isProtectedRoute = !isAuthRoute && !isPublicRoute;
  
  // If the user is logged in
  if (user) {
    // If user tries to access an auth route (e.g., /login), redirect to dashboard
    if (isAuthRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } 
  // If the user is not logged in
  else {
    // If the user is trying to access a protected route, redirect to login
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
