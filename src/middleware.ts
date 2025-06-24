
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

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
        set(name: string, value: string, options: CookieOptions) {
          // If the cookie is updated, update the cookies on the response.
          response.cookies.set({
            name,
            value,
            ...options,
          })
        },
        remove(name: string, options: CookieOptions) {
          // If the cookie is removed, delete it from the response.
          response.cookies.delete(name, options)
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()
  const { pathname } = request.nextUrl

  // Define routes that are accessible only to authenticated users
  const protectedRoutes = [
    '/dashboard',
    '/chat',
    '/inventory',
    '/import',
    '/dead-stock',
    '/suppliers',
    '/analytics',
    '/alerts',
    '/test-supabase'
  ];
  
  // Define routes that are accessible only to unauthenticated users
  const authRoutes = ['/login', '/signup'];

  const isProtectedRoute = protectedRoutes.some(route => pathname.startsWith(route));
  const isAuthRoute = authRoutes.includes(pathname);

  // 1. Redirect unauthenticated users from protected routes to the login page
  if (!user && isProtectedRoute) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  // 2. Redirect authenticated users from auth routes to the dashboard
  if (user && isAuthRoute) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  // 3. Handle the root path ('/') explicitly
  if (pathname === '/') {
    if (user) {
      // If logged in, go to dashboard
      return NextResponse.redirect(new URL('/dashboard', request.url));
    } else {
      // If logged out, go to login
      return NextResponse.redirect(new URL('/login', request.url));
    }
  }

  // Allow the request to proceed if none of the above conditions are met.
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
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel).*)',
  ],
}
