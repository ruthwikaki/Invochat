
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

// The middleware is responsible for refreshing the session cookie and redirecting
// users based on their authentication state.
export async function middleware(req: NextRequest) {
  // We need to create a response object to be able to set the cookie.
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  // Create a Supabase client that can read and write cookies.
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the request's cookies.
          req.cookies.set({ name, value, ...options });
          // And update the response's cookies.
          res = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the request's cookies.
          req.cookies.set({ name, value: '', ...options });
          // And update the response's cookies.
          res = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // Refresh session if expired - important for Server Components
  // https://supabase.com/docs/guides/auth/auth-helpers/nextjs#managing-session-with-middleware
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = req.nextUrl;

  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

  // Handle the root path explicitly.
  if (pathname === '/') {
    return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', req.url));
  }

  // If user is not logged in, protect routes.
  if (!user) {
    if (!isAuthRoute && !isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
    return res;
  }
  
  // If user is logged in, handle redirects for auth and setup pages.
  const companyId = user.app_metadata?.company_id;

  if (isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  if (!companyId) {
    if (!isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url));
    }
  } else {
    if (isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
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
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel).*)',
  ],
};
