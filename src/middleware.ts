
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!supabaseUrl || !supabaseAnonKey) {
    // If Supabase credentials aren't provided, we can't do anything.
    // This might happen in development if the .env file is not set up.
    // The app will likely fail to render, but at least the middleware won't crash.
    return response
  }

  const supabase = createServerClient(supabaseUrl, supabaseAnonKey, {
    cookies: {
      get(name: string) {
        return request.cookies.get(name)?.value
      },
      set(name: string, value: string, options: CookieOptions) {
        // If the cookie is set, update the request's cookies.
        request.cookies.set({ name, value, ...options })
        // Also update the response's cookies.
        response.cookies.set({ name, value, ...options })
      },
      remove(name: string, options: CookieOptions) {
        // If the cookie is removed, update the request's cookies.
        request.cookies.set({ name, value: '', ...options })
        // Also update the response's cookies.
        response.cookies.set({ name, value: '', ...options })
      },
    },
  })

  // This will refresh the session if it's expired.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  // Define protected and auth routes
  const protectedRoutes = ['/dashboard', '/chat', '/inventory', '/import', '/dead-stock', '/suppliers', '/analytics', '/alerts'];
  const isProtectedRoute = protectedRoutes.some(p => pathname.startsWith(p));

  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.some(p => pathname.startsWith(p));

  if (!user && isProtectedRoute) {
    // If user is not logged in and tries to access a protected route, redirect to login.
    return NextResponse.redirect(new URL('/login', request.url))
  }

  if (user && isAuthRoute) {
    // If user is logged in and tries to access login/signup, redirect to dashboard.
    return NextResponse.redirect(new URL('/dashboard', request.url))
  }

  if (pathname === '/') {
    // If user lands on the root, redirect based on auth state.
    return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', request.url));
  }

  return response
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - api (API routes)
     */
    '/((?!_next/static|_next/image|favicon.ico|api).*)',
  ],
}
