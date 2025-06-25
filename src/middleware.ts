
import { createServerClient, type CookieOptions } from '@supabase/ssr';
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

  // This refreshes the session cookie if it's expired.
  const { data: { user } } = await supabase.auth.getUser();

  const { pathname } = req.nextUrl;
  const isAuthRoute = ['/login', '/signup'].includes(pathname);

  // If the user is not logged in, redirect them to the login page
  // unless they are already on a public route.
  if (!user && !isAuthRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // If the user is logged in, redirect them to the dashboard
  // if they try to access an auth route or the root.
  if (user && (isAuthRoute || pathname === '/')) {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }
  
  // Continue with the request, potentially with an updated session cookie.
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
