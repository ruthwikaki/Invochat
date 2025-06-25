
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  // Create a Supabase client that can read and write cookies for the server.
  // This is used to refresh the session.
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
    }
  )

  // This will refresh the session if it's expired.
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)
  const publicRoutes = ['/quick-test'];
  const isPublicRoute = publicRoutes.includes(pathname);

  // If user is not logged in, redirect them to the login page,
  // unless they are trying to access an auth page or a public/diagnostic page.
  if (!user && !isAuthRoute && !isPublicRoute) {
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
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }

    const companyId = user.app_metadata?.company_id
    const isSetupIncompleteRoute = pathname === '/setup-incomplete'

    // If setup is incomplete (no companyId), redirect to the setup page.
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test pages even if setup is incomplete
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', request.url))
      }
    }

    // If setup IS complete, but they somehow land on the setup page, redirect them away.
    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', request.url))
    }
  }

  // Return the response object, which may have new cookies set.
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
}
