
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';

export async function middleware(req: NextRequest) {
  // Start with a single response object that can be mutated
  const res = NextResponse.next();

  const isProd = process.env.NODE_ENV === 'production';

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
            path: '/',
            secure: isProd,
            sameSite: 'lax',
            httpOnly: true,
          });
        },
        remove(name: string, options: CookieOptions) {
          res.cookies.set({
            name,
            value: '',
            ...options,
            path: '/',
            maxAge: 0,
          });
        },
      },
    }
  );

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  // First, try to get the session from cookies (fast)
  const { data: { session } } = await supabase.auth.getSession();

  // If user is authenticated
  if (session) {
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
    if (pathname === '/') {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }

    const companyId = session.user.app_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    if (!companyId && !isSetupIncompleteRoute) {
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    }

    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
    
    return res;
  }

  // If user is not authenticated and trying to access a protected route
  if (!isAuthRoute && !isPublicRoute) {
    // As a fallback, try getUser to double-check with the server (slower)
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.redirect(new URL('/login', req.url));
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
     * - public (public files)
     * - api (API routes)
     */
    '/((?!_next/static|_next/image|favicon.ico|public|api).*)',
  ],
};
