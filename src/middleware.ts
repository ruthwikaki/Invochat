
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  })

  // Create a Supabase client that can be used in Server Components, API Routes, and middleware
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the request's cookies.
          req.cookies.set({ name, value, ...options })
          // Also update the response's cookies.
          res.cookies.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the request's cookies.
          req.cookies.set({ name, value: '', ...options })
          // Also update the response's cookies.
          res.cookies.set({ name, value: '', ...options })
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = req.nextUrl
  
  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)
  const isSetupIncompleteRoute = pathname === '/setup-incomplete'
  const isTestRoute = pathname === '/test-supabase';

  // If user is not logged in, redirect to login page if not on an auth route.
  if (!user) {
    if (isAuthRoute || isSetupIncompleteRoute) {
      return res
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

  return res
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
