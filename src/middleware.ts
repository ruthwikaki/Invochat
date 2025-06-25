import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // Create a response object that we'll potentially modify
  let res = NextResponse.next({
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
          // Set the cookie on both request and response
          req.cookies.set({ name, value, ...options });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          // Remove the cookie from both request and response
          req.cookies.set({ name, value: '', ...options });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  // IMPORTANT: Refresh the session to ensure it's valid
  const { data: { session }, error } = await supabase.auth.getSession();
  
  // If there's an error getting the session, log it
  if (error) {
    console.error('Middleware: Error getting session:', error);
  }
  
  const user = session?.user;
  const { pathname } = req.nextUrl;
  
  // Define auth routes and setup routes
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isSetupIncompleteRoute = pathname === '/setup-incomplete';

  // Handle the root path
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
  
  // If user is logged in, handle redirects and setup checks
  const companyId = user.app_metadata?.company_id;

  // Redirect away from auth pages if already logged in
  if (isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  // Check for incomplete setup
  if (!companyId) {
    if (!isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url));
    }
  } else {
    if (isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  // Return the response with potentially updated cookies
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