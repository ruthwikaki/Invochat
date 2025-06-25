
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  const res = NextResponse.next({
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
  const isTestRoute = pathname === '/test-supabase';
  const isHomePage = pathname === '/';

  // If user is not logged in
  if (!user) {
    if (isAuthRoute || isSetupIncompleteRoute) {
      return res
    }
    return NextResponse.redirect(new URL('/login', req.url))
  }
  
  // If user is logged in
  if (isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }

  // Handle root path redirect for logged-in users
  if (isHomePage) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
  }

  const companyId = user.app_metadata?.company_id;

  if (!companyId) {
    if (!isSetupIncompleteRoute && !isTestRoute) {
      return NextResponse.redirect(new URL('/setup-incomplete', req.url))
    }
  } else {
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
