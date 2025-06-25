
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  // The createServerClient function needs to be called in a middleware or route handler.
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the request's cookies.
          request.cookies.set({
            name,
            value,
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
          // Also update the response's cookies.
          response.cookies.set({
            name,
            value,
            ...options,
          })
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the request's cookies.
          request.cookies.set({
            name,
            value: '',
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
          // Also update the response's cookies.
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
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl
  
  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)

  // If user is not logged in, redirect them to the login page...
  // ...unless they are trying to access an auth page.
  if (!user && !isAuthRoute) {
    // Allow access to the root page and quick-test page for diagnostics.
    if (pathname === '/quick-test') {
        return response;
    }
    return NextResponse.redirect(new URL('/login', request.url))
  }
  
  // If user is logged in, handle redirects and setup checks.
  if (user) {
    // If they are on an auth route, redirect to dashboard.
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
    
    // Redirect from root to dashboard.
    if (pathname === '/') {
        return NextResponse.redirect(new URL('/dashboard', request.url));
    }

    const companyId = user.app_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    // If setup is incomplete (no companyId), redirect to setup page.
    // This logic prevents a redirect loop by not redirecting if they are already on the setup page.
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test routes for debugging purposes.
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', request.url))
      }
    }
    
    // If setup is complete, but they are on the setup page, they don't belong there.
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
