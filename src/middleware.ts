
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => req.cookies.get(name)?.value,
        set: (name, value, options) => res.cookies.set(name, value, options),
        remove: (name, options) => res.cookies.delete(name, options),
      },
    }
  );

  const { data: { session } } = await supabase.auth.getSession();
  const user = session?.user;

  const { pathname } = req.nextUrl;

  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

  // If user is not logged in
  if (!user) {
    // If they are trying to access a protected route, redirect to login
    if (!isAuthRoute && pathname !== '/') {
      return NextResponse.redirect(new URL('/login', req.url));
    }
    // If they are on the root, redirect to login
    if (pathname === '/') {
        return NextResponse.redirect(new URL('/login', req.url));
    }
    // Allow access to auth routes
    return res;
  }

  // If user is logged in
  const companyId = user.app_metadata?.company_id;

  // If user is logged in but their account setup is incomplete
  if (!companyId) {
    // If they are not already on the setup page, redirect them there
    if (!isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url));
    }
    // Allow access to the setup page
    return res;
  }

  // If user is logged in and setup is complete
  // If they are trying to access an auth route or the root, redirect to dashboard
  if (isAuthRoute || pathname === '/') {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }
  
  // If they are trying to access the setup-incomplete page, but they are already setup, redirect to dashboard
  if(isSetupIncompleteRoute) {
     return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  // Allow access to all other protected routes
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
