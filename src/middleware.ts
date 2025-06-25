import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // We need to create a response and hand it to the supabase client to be able to modify the cookies.
  const res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  // Create a Supabase client configured to use cookies
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the response cookies.
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the response cookies.
          res.cookies.delete(name, options);
        },
      },
    }
  );

  // IMPORTANT: The `getSession` method will refresh the session if it's expired.
  const { data: { session } } = await supabase.auth.getSession();
  
  const user = session?.user;
  const { pathname } = req.nextUrl;
  
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

  // Handle the root path, redirecting based on auth state
  if (pathname === '/') {
    return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', req.url));
  }

  // If user is not logged in, protect all non-auth routes
  if (!user) {
    if (!isAuthRoute && !isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
    return res;
  }
  
  // If user is logged in, handle redirects away from auth pages
  // and handle the setup-incomplete case.
  const companyId = user.app_metadata?.company_id;

  if (isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  if (!companyId) {
    // If user is missing company_id, redirect to setup page, unless they are already there.
    if (!isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url));
    }
  } else {
    // If user has a company_id, they should not be on the setup page.
    if (isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  // If all checks pass, return the original response, which now has the updated cookie.
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
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel).*)',
  ],
};
