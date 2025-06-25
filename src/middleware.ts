
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // Create a response object that we can modify and return
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  // Create a Supabase client that can read/write cookies
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // The middleware is the only place that can set cookies on the response.
          // We update the cookies on both the request and the response objects.
          req.cookies.set({ name, value, ...options });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // The middleware is the only place that can remove cookies on the response.
          // We update the cookies on both the request and the response objects.
          req.cookies.set({ name, value: '', ...options });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // IMPORTANT: This call will refresh the session if it's expired.
  // It will then use the `set` cookie method above to send the new cookie back
  // to the browser on the response.
  const { data: { session } } = await supabase.auth.getSession();
  
  const user = session?.user;
  const { pathname } = req.nextUrl;
  
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

  // Handle the root path ('/')
  if (pathname === '/') {
    return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', req.url));
  }

  // If the user is not logged in, protect all routes except for auth and setup pages.
  if (!user) {
    if (!isAuthRoute && !isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
    return res;
  }
  
  // If the user is logged in, handle redirects away from auth pages
  // and check if their account setup is complete.
  const companyId = user.app_metadata?.company_id;

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

  // All checks have passed, so return the response with the potentially updated session cookie.
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
