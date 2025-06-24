import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  // This is the crucial part: we are cloning the request headers and creating a response object
  // that we can safely modify and return.
  const response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('Supabase credentials not found. Middleware is skipping authentication.');
    // Still return the created response
    return response;
  }

  const supabase = createServerClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        // The `get` function is straightforward.
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        // The `set` function updates the cookies on the `response` object.
        set(name: string, value: string, options: CookieOptions) {
          response.cookies.set({ name, value, ...options })
        },
        // The `remove` function deletes the cookie from the `response` object.
        remove(name: string, options: CookieOptions) {
          response.cookies.set({ name, value: '', ...options })
        },
      },
    }
  );

  // This will refresh the session if it's expired and update the cookie in the response.
  const { data: { user } } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;

  const protectedRoutes = ['/dashboard', '/chat', '/inventory', '/import', '/dead-stock', '/suppliers', '/analytics', '/alerts'];
  const isProtectedRoute = protectedRoutes.some(p => pathname.startsWith(p));

  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.some(p => pathname.startsWith(p));

  if (!user && isProtectedRoute) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (user && isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }
  
  if (pathname === '/') {
    return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', request.url));
  }

  // Return the response object, which now has the updated session cookie if it was refreshed.
  return response
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * Feel free to modify this pattern to include more paths.
     */
    '/((?!_next/static|_next/image|favicon.ico).*)',
  ],
}
