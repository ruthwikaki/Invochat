
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const isProd = process.env.NODE_ENV === 'production';

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
          res.cookies.set({
            name,
            value,
            ...options,
            path: '/', // Crucial for cookie visibility across the app
            secure: isProd, // Use secure cookies in production
          });
        },
        remove(name: string, options: CookieOptions) {
          res.cookies.set({
            name,
            value: '',
            ...options,
            path: '/',
            maxAge: -1, // A common way to delete a cookie
          });
        },
      },
    }
  );

  // Refresh session if expired - this will set new cookies on the response.
  const { data: { session } } = await supabase.auth.getSession();

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const publicRoutes = ['/quick-test'];

  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  // If user is not signed in and the route is not public or an auth route, redirect to login
  if (!session && !isAuthRoute && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  if (session) {
    // If user is signed in and on an auth route, redirect to dashboard
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
    // If user is signed in and at the root, redirect to dashboard
    if (pathname === '/') {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }

    // Handle incomplete account setup
    const companyId = session.user.app_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    // If companyId is missing and they are not on the setup page, redirect them
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test pages even if setup is incomplete
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    }

    // If companyId exists and they land on the setup page, redirect to dashboard
    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  // Return the response, which may have been modified with new cookies
  return res;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)'],
};
