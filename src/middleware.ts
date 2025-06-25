
import { NextResponse, type NextRequest } from 'next/server'
import { createMiddlewareClient } from '@supabase/auth-helpers-nextjs'

export async function middleware(req: NextRequest) {
  const res = NextResponse.next()
  const supabase = createMiddlewareClient({ req, res })

  // This will read your sb-access-token / sb-refresh-token cookies automatically.
  const {
    data: { session },
  } = await supabase.auth.getSession()

  const { pathname } = req.nextUrl
  const authRoutes = ['/login', '/signup']
  const publicRoutes = ['/quick-test']

  const isAuthRoute = authRoutes.includes(pathname)
  const isPublicRoute = publicRoutes.includes(pathname)

  if (!session && !isAuthRoute && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url))
  }
  
  if (session) {
    if (isAuthRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url))
    }
    if (pathname === '/') {
        return NextResponse.redirect(new URL('/dashboard', req.url))
    }
    
    const companyId = session.user.app_metadata?.company_id
    const isSetupIncompleteRoute = pathname === '/setup-incomplete'

    // If setup is incomplete (no companyId), redirect to the setup page.
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test pages even if setup is incomplete
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url))
      }
    }

    // If setup IS complete, but they somehow land on the setup page, redirect them away.
    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url))
    }
  }

  return res
}

export const config = {
  matcher: [ '/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)' ],
}
