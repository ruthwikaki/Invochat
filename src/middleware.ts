
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  // This `response` object is the single source of truth for all cookie operations.
  let response = NextResponse.next({
    request: {
      headers: req.headers,
    },
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // The Supabase client will call this method when it needs to set a cookie.
          // We update the cookies on both the request and response objects.
          req.cookies.set({ name, value, ...options })
          response.cookies.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          // The Supabase client will call this method when it needs to remove a cookie.
          // We update the cookies on both the request and response objects.
          req.cookies.set({ name, value: '', ...options })
          response.cookies.set({ name, value: '', ...options })
        },
      },
    }
  )

  // Refresh session if expired - this will call the `set` cookie handler if the session is updated.
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = req.nextUrl
  
  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)
  const isSetupIncompleteRoute = pathname === '/setup-incomplete'
  const isTestRoute = pathname === '/test-supabase';

  // If user is not logged in, redirect to login page if not on an auth route.
  if (!user) {
    if (isAuthRoute || isSetupIncompleteRoute) {
      return response
    }
    return NextResponse.redirect(new URL('/login', req.url))
  }
  
  // If user is logged in, handle redirects and setup checks.
  
  // Redirect away from auth pages if already logged in.
  if (isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }

  const companyId = user.app_metadata?.company_id;

  // If user lacks company_id, force them to the setup page.
  // Allow access to the test page to help debug.
  if (!companyId) {
    if (!isSetupIncompleteRoute && !isTestRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url))
    }
  } else {
    // If user has company_id but is on the setup page, send them away.
    if (isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url))
    }
  }

  // Return the response object, which may have been modified by the Supabase client.
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
