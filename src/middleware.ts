
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  // Create a response object that we can modify
  const res = NextResponse.next()

  // Create a Supabase client that can read and write cookies
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => req.cookies.get(name)?.value,
        set: (name, value, options) => res.cookies.set(name, value, options),
        remove: (name, options) => res.cookies.delete(name, options),
      },
    }
  )

  // Refresh session if expired - this will write a new cookie to `res` if needed
  const { data: { user } } = await supabase.auth.getUser()

  const { pathname } = req.nextUrl
  const authRoutes = ['/login', '/signup'];
  const isAuthRoute = authRoutes.includes(pathname);

  // If the user is not signed in and the current path is not an auth route,
  // redirect the user to the login page.
  if (!user && !isAuthRoute) {
    return NextResponse.redirect(new URL('/login', req.url))
  }

  // If the user is signed in and the current path is an auth route or the root,
  // redirect the user to the dashboard.
  if (user && (isAuthRoute || pathname === '/')) {
    return NextResponse.redirect(new URL('/dashboard', req.url))
  }
  
  // If we've gotten here, the user is authenticated and on a protected route,
  // or they are unauthenticated and on an auth route.
  // The `res` object has the potentially updated session cookie.
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
     */
    '/((?!_next/static|_next/image|favicon.ico|api|_vercel).*)',
  ],
}
