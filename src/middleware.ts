
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
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
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

  const publicRoutes = [
    '/login',
    '/signup',
    '/forgot-password',
    '/update-password',
    '/database-setup',
    '/env-check',
  ];

  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));

  if (!req.cookies.has(CSRF_COOKIE_NAME)) {
    const csrfToken = generateCSRFToken();
    response.cookies.set({
      name: CSRF_COOKIE_NAME,
      value: csrfToken,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      httpOnly: false, 
      path: '/',
    });
  }

  if (user) {
    const companyId = user.app_metadata?.company_id;
    if (!companyId && pathname !== '/env-check' && pathname !== '/database-setup') {
      return NextResponse.redirect(new URL('/env-check', req.url));
    }
    if (isPublicRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } else {
    if (!isPublicRoute && pathname !== '/') {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }

  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public|api).*)'],
};
