import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';

export async function middleware(req: NextRequest) {
  console.log(`[Middleware] Path: ${req.nextUrl.pathname}, Method: ${req.method}`);
  // Start with a single response object that can be mutated
  const res = NextResponse.next();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          res.cookies.set({
            name,
            value,
            ...options,
            // Don't override cookie options from Supabase
            // Let Supabase handle httpOnly, secure, and sameSite settings
          });
        },
        remove(name: string, options: CookieOptions) {
          res.cookies.set({
            name,
            value: '',
            ...options,
            maxAge: 0,
          });
        },
      },
    }
  );

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  try {
    // First, try to get the session from cookies (fast)
    const { data: { session } } = await supabase.auth.getSession();

    // If user is authenticated
    if (session) {
      if (isAuthRoute) {
        console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /dashboard`);
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
      if (pathname === '/') {
        console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /dashboard`);
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }

      const companyId = session.user.app_metadata?.company_id;
      const isSetupIncompleteRoute = pathname === '/setup-incomplete';

      if (!companyId && !isSetupIncompleteRoute) {
        if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
          console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /setup-incomplete`);
          return NextResponse.redirect(new URL('/setup-incomplete', req.url));
        }
      }

      if (companyId && isSetupIncompleteRoute) {
        console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /dashboard`);
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
      
      return res;
    }

    // If user is not authenticated and trying to access a protected route
    if (!isAuthRoute && !isPublicRoute) {
      // As a fallback, try getUser to double-check with the server (slower)
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /login`);
        return NextResponse.redirect(new URL('/login', req.url));
      }
    }
  } catch (error) {
    console.error('Middleware auth error:', error);
    // On error, redirect to login for protected routes
    if (!isAuthRoute && !isPublicRoute) {
      console.log(`[Middleware] Redirecting from ${req.nextUrl.pathname} to /login due to error`);
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  
  return res;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - public (public files)
     * - api (API routes)
     */
    '/((?!_next/static|_next/image|favicon.ico|public|api).*)',
  ],
};
