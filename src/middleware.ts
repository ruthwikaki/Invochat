
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // We need to create a response and hand it to the supabase client.
  // This will allow the client to send back updated cookies after refreshing the session.
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
          // The `set` method is called by the Supabase client when the session is refreshed.
          // We pass this new cookie to the response so it can be set on the browser.
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // The `remove` method is called by the Supabase client when the user signs out.
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // IMPORTANT: This call will refresh the session if it's expired.
  // It also returns the user object.
  const { data: { user } } = await supabase.auth.getUser();

  const { pathname } = req.nextUrl;
  
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

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
      if (!isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    } else {
      // If the user has a company_id but is on the setup page, send them to the dashboard.
      if (isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
    }
  }

  // All checks have passed. Return the response, which may have an updated
  // 'Set-Cookie' header from the session refresh.
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
