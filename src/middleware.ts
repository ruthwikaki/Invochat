
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next({
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
          req.cookies.set({ name, value, ...options });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          req.cookies.set({ name, value: '', ...options });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();

  const { pathname } = req.nextUrl;
  
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';
  const isTestRoute = pathname === '/test-supabase';

  // Handle the root path, redirecting based on auth state.
  if (pathname === '/') {
    const redirectTo = user ? '/dashboard' : '/login';
    return NextResponse.redirect(new URL(redirectTo, req.url));
  }

  // If the user is not logged in, protect all routes except for auth and setup pages.
  if (!user) {
    if (!isAuthRoute && !isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  // If the user is logged in, handle redirects and setup checks.
  else {
    const companyId = user.app_metadata?.company_id;

    // Redirect away from auth pages if already logged in.
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }

    // If the user is missing a company_id, send them to the setup page.
    if (!companyId) {
      // Allow access to the test page even without a companyId to help debug.
      if (!isSetupIncompleteRoute && !isTestRoute) {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    } else {
      // If the user has a company_id but is on the setup page, send them to the dashboard.
      if (isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
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
     * - api (API routes)
     * - _vercel (Vercel specific files)
     * - public (public files)
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)',
  ],
};
