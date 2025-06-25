
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();

  // Create a Supabase client that can read and write cookies.
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

  // This will refresh the session if it's expired.
  const { data: { session } } = await supabase.auth.getSession();
  const user = session?.user;

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isRoot = pathname === '/';

  // If the user is logged in...
  if (user) {
    // and they try to access an auth route or the root page, redirect to the dashboard.
    if (isAuthRoute || isRoot) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  } 
  // If the user is not logged in...
  else {
    // and they try to access any protected route (i.e., not an auth route), redirect to login.
    if (!isAuthRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }

  // Allow the request to proceed, potentially with an updated session cookie.
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
