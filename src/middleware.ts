
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('Supabase credentials not found. Middleware is skipping authentication.');
    return response;
  }

  const supabase = createServerClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // A middleware can't set cookies on a request, only on a response.
          // So we're modifying the response object here.
          response.cookies.set({
            name,
            value,
            ...options,
          })
        },
        remove(name: string, options: CookieOptions) {
          // A middleware can't remove cookies from a request, only on a response.
          // So we're modifying the response object here.
          response.cookies.set({
            name,
            value: '',
            ...options,
          })
        },
      },
    }
  )

  // This will refresh the session if it's expired.
  // It's important that this is called *before* the redirect logic.
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  // Define routes that require authentication
  const protectedRoutes = ['/dashboard', '/chat', '/inventory', '/import', '/dead-stock', '/suppliers', '/analytics', '/alerts'];
  const isProtectedRoute = protectedRoutes.some(p => pathname.startsWith(p));

  // Define auth routes
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.some(p => pathname.startsWith(p));

  if (!user && isProtectedRoute) {
    // If no user, and it's a protected route, redirect to login
    return NextResponse.redirect(new URL('/login', request.url));
  }

  if (user && isAuthRoute) {
    // If user is logged in and tries to access login/signup, redirect to dashboard
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }
  
  if (pathname === '/') {
    // Redirect root to either dashboard or login
    if (user) {
        return NextResponse.redirect(new URL('/dashboard', request.url));
    }
    return NextResponse.redirect(new URL('/login', request.url));
  }

  // If we've gotten this far, the user is allowed to access the route.
  // We return the response object, which may have had its cookies updated by `getUser`.
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
