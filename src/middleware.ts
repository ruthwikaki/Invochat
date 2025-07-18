
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

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

  const publicRoutes = ['/login', '/signup', '/forgot-password', '/update-password', '/'];

  // Special handling for initial setup pages
  if (pathname.startsWith('/database-setup') || pathname.startsWith('/env-check')) {
    return response;
  }
  
  const isPublicRoute = publicRoutes.some(route => pathname === route);
  
  // If the user is not logged in and is trying to access a protected route, redirect to login.
  if (!user && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // If the user IS logged in but doesn't have a company_id, they need to run the setup script.
  if (user && !user.app_metadata.company_id) {
    // Allow access to the env-check page, but redirect from anywhere else.
    if (!pathname.startsWith('/env-check')) {
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
     * - api/ (API routes which have their own auth)
     */
    '/((?!_next/static|_next/image|favicon.ico|api/).*)',
  ],
}
