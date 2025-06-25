
import { NextResponse, type NextRequest } from 'next/server'
import { createServerClient } from '@supabase/ssr'

// This middleware is the cornerstone of the authentication system.
// It runs before any route is rendered and performs two critical tasks:
// 1. Session Refresh: It refreshes the user's session cookie if it has expired.
// 2. Route Protection: It redirects users based on their authentication state.
export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options) {
          request.cookies.set({ name, value, ...options })
          response = NextResponse.next({
            request: { headers: request.headers },
          })
          response.cookies.set({ name, value, ...options })
        },
        remove(name: string, options) {
          request.cookies.set({ name, value: '', ...options })
          response = NextResponse.next({
            request: { headers: request.headers },
          })
          response.cookies.set({ name, value: '', ...options })
        },
      },
    }
  )

  // This will refresh the session if it's expired
  const { data: { user } } = await supabase.auth.getUser()
  const { pathname } = request.nextUrl
  
  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)

  // If user is not logged in, redirect them to the login page,
  // unless they are trying to access an auth page or a diagnostic page.
  if (!user && !isAuthRoute) {
    if (pathname === '/quick-test') {
        return response;
    }
    return NextResponse.redirect(new URL('/login', request.url))
  }
  
  // If user is logged in, handle redirects and setup checks.
  if (user) {
    // If they are on an auth route, they shouldn't be. Redirect to dashboard.
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
    
    // Redirect from the root path to the dashboard.
    if (pathname === '/') {
        return NextResponse.redirect(new URL('/dashboard', request.url));
    }

    const companyId = user.app_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    // If setup is incomplete (no companyId), redirect to the setup page.
    // This logic prevents a redirect loop by NOT redirecting if they are already there.
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test routes for debugging purposes, even if setup is incomplete.
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', request.url))
      }
    }
    
    // If setup IS complete, but they somehow land on the setup page, redirect them away.
    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
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
     * - _vercel (Vercel specific files)
     * - public (public files)
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)',
  ],
};
