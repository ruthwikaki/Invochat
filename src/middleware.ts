
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
  
  console.log('🔍 Middleware executing for path:', pathname);
  console.log('🔑 Supabase URL exists:', !!supabaseUrl);
  console.log('🔑 Supabase Anon Key exists:', !!supabaseAnonKey);


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
  const publicRoutes = ['/', '/login', '/signup', '/forgot-password', '/update-password', '/database-setup', '/env-check'];
  const isPublicRoute = publicRoutes.some(route => pathname === route);
  
  console.log('👤 User authenticated:', !!user);
  console.log('🛡️ Is public route:', isPublicRoute);


  // If the user is logged in
  if (user) {
    // If the user is on a public-only route (like login/signup), redirect them to the dashboard.
    if (isPublicRoute && pathname !== '/') {
        console.log('➡️ Redirecting authenticated user from public route to /dashboard');
        return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } 
  // If the user is not logged in
  else {
    // If the user is trying to access a protected route, redirect them to the login page.
    if (!isPublicRoute) {
      console.log('➡️ Redirecting unauthenticated user to /login');
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }

  if (pathname === '/') {
    console.log('🏠 Root path logic. User:', !!user, 'Redirecting to:', user ? '/dashboard' : '/login');
    if (user) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
    } else {
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
