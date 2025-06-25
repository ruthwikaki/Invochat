
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  // Create a response object to modify
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  })

  // Create a Supabase client that can be used in Server Components
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is set, update the request's cookies
          // and the response's cookies
          req.cookies.set({ name, value, ...options })
          // It's important to update the response object here
          // so the browser receives the new cookie
          res.cookies.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, update the request's cookies
          // and the response's cookies
          req.cookies.set({ name, value: '', ...options })
          res.cookies.set({ name, value: '', ...options })
        },
      },
    }
  )

  // This will refresh the session if it's expired
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = req.nextUrl
  
  const authRoutes = ['/login', '/signup']
  const isAuthRoute = authRoutes.includes(pathname)
  const isSetupIncompleteRoute = pathname === '/setup-incomplete'
  const isHomePage = pathname === '/';

  // If user is not logged in, protect routes
  if (!user) {
    if (isAuthRoute || isSetupIncompleteRoute) {
      // Allow access to login, signup, and setup-incomplete pages
      return res
    }
    // For all other routes, redirect to login
    return NextResponse.redirect(new URL('/login', req.url))
  }
  
  // If user is logged in
  if (isAuthRoute) {
    // Redirect away from login/signup pages
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }

  if (isHomePage) {
    // Redirect from root to dashboard
    return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  // Check if user setup is complete (company_id exists)
  const companyId = user.app_metadata?.company_id;

  if (!companyId) {
    // If setup is incomplete, redirect to the setup page,
    // unless they are already on it or the test page.
    if (pathname !== '/setup-incomplete' && pathname !== '/test-supabase') {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url))
    }
  } else {
    // If setup is complete, they should not be on the setup page.
    if (isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url))
    }
  }

  // Return the response object, which may have new cookies set
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
