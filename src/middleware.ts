
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { logger } from './lib/logger';
import { generateCSRFToken, CSRF_COOKIE_NAME } from './lib/csrf';

export async function middleware(req: NextRequest) {
  const response = NextResponse.next();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          req.cookies.set({ name, value, ...options });
          response.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          req.cookies.set({ name, value: '', ...options });
          response.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();

  // CSRF Protection: Ensure a token cookie exists.
  // The client will read from this cookie and include it in form submissions.
  let csrfToken = req.cookies.get(CSRF_COOKIE_NAME)?.value;
  if (!csrfToken) {
    csrfToken = generateCSRFToken();
    response.cookies.set({
      name: CSRF_COOKIE_NAME,
      value: csrfToken,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      path: '/',
    });
  }

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup', '/forgot-password', '/update-password'];
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  try {
    if (user) {
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
      if (!isAuthRoute && !isPublicRoute && pathname !== '/update-password') {
        return NextResponse.redirect(new URL('/login', req.url));
      }
    }
  } catch (error) {
    logger.error('[Middleware] Error:', error);
    if (!isAuthRoute && !isPublicRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public|api).*)'],
};
