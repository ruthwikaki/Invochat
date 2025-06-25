
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // Create a response object that we can modify and return.
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  // Create a Supabase client that can read/write cookies.
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
          // We pass this new cookie to the request and the response so it can be set on the browser
          // and available to subsequent server components.
          req.cookies.set({ name, value, ...options });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // The `remove` method is called by the Supabase client when the user signs out.
          req.cookies.set({ name, value: '', ...options });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // IMPORTANT: This call will refresh the session if it's expired.
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

  // If the user is not logged in, protect all routes except for auth routes.
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

    // Check for incomplete setup.
    if (!companyId) {
      if (!isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    } else {
      if (isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
    }
  }

  // Return the response with the potentially updated session cookie.
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
