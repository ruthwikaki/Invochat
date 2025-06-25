
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();

  // Create a Supabase client that can read and write cookies
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

  // Refresh session if expired - this will write a new cookie to `res` if needed
  const { data: { user } } = await supabase.auth.getUser();

  const { pathname } = req.nextUrl;

  const publicRoutes = ['/login', '/signup'];
  const isPublicRoute = publicRoutes.includes(pathname);

  // If the user is not signed in and is trying to access a protected route,
  // redirect them to the login page.
  if (!user && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // If the user is signed in and is trying to access a public route (like login)
  // or the root path, redirect them to the dashboard.
  if (user && (isPublicRoute || pathname === '/')) {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }
  
  // If none of the above conditions are met, continue with the response.
  // This `res` object might have a new 'Set-Cookie' header if the session was refreshed.
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
