
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { logger } from './lib/logger';
import { generateCSRFToken, CSRF_COOKIE_NAME } from './lib/csrf';

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
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the request cookies as well.
          // This will make sure that the server component is aware of the session.
          req.cookies.set({
            name,
            value,
            ...options,
          });
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({
            name,
            value,
            ...options,
          });
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the request cookies as well.
          req.cookies.set({
            name,
            value: '',
            ...options,
          });
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({
            name,
            value: '',
            ...options,
          });
        },
      },
    }
  );

  // CSRF Protection: Set cookie on all requests
  // This cookie is NOT httpOnly, so it can be read by client-side script
  // to be included in form submissions.
  const csrfToken = req.cookies.get(CSRF_COOKIE_NAME)?.value;
  if (!csrfToken) {
    const newCsrfToken = generateCSRFToken();
    response.cookies.set({
      name: CSRF_COOKIE_NAME,
      value: newCsrfToken,
      httpOnly: false, // Must be readable by client-side script
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/',
    });
  }

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  try {
    const { data: { user } } = await supabase.auth.getUser();

    // If user is authenticated
    if (user) {
      // Allow access to update-password page if there's a recovery code
      if (pathname === '/update-password' && req.nextUrl.searchParams.has('code')) {
        return response;
      }

      if (isAuthRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
      if (pathname === '/') {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }

      const companyId = user.app_metadata?.company_id || user.user_metadata?.company_id;
      const isSetupIncompleteRoute = pathname === '/setup-incomplete';

      if (!companyId && !isSetupIncompleteRoute) {
        if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
          return NextResponse.redirect(new URL('/setup-incomplete', req.url));
        }
      }

      if (companyId && isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
    } else {
      // If user is not authenticated and trying to access a protected route
      if (!isAuthRoute && !isPublicRoute && pathname !== '/update-password') {
        return NextResponse.redirect(new URL('/login', req.url));
      }
    }
  } catch (error) {
    logger.error('[Middleware] Error:', error);
    // On error, allow access to auth routes but protect others
    if (!isAuthRoute && !isPublicRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public|api).*)'],
};
