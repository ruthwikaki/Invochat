
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { logger } from './lib/logger';
import { generateCSRFToken, CSRF_COOKIE_NAME } from './lib/csrf';

export async function middleware(req: NextRequest) {
  // Create the response object ONCE at the beginning.
  const response = NextResponse.next({
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
          // Mutate the request cookies for the current lifecycle
          req.cookies.set({
            name,
            value,
            ...options,
          });
          // Mutate the single response object's cookies for the client
          response.cookies.set({
            name,
            value,
            ...options,
          });
        },
        remove(name: string, options: CookieOptions) {
          // Mutate the request cookies
          req.cookies.set({
            name,
            value: '',
            ...options,
          });
          // Mutate the response cookies
          response.cookies.set({
            name,
            value: '',
            ...options,
          });
        },
      },
    }
  );

  // This will now use the handlers above, which mutate the single `response` object.
  const { data: { user } } = await supabase.auth.getUser();

  // CSRF Protection: Set cookie on the same response object AFTER Supabase has run.
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
