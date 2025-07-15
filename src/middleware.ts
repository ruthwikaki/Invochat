
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  const publicRoutes = [
    '/login',
    '/signup',
    '/forgot-password',
    '/update-password',
    '/env-check',
    '/database-setup'
  ];

  // This is a static asset, let it pass
  if (pathname.startsWith('/_next') || pathname.startsWith('/api') || pathname.endsWith('.ico') || pathname.endsWith('.png')) {
    return NextResponse.next();
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          req.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
           req.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  const { data: { session } } = await supabase.auth.getSession();

  const isPublicRoute = publicRoutes.some(route => pathname.startsWith(route));

  if (!session && !isPublicRoute) {
    // If not logged in and not on a public route, redirect to login
    return NextResponse.redirect(new URL('/login', req.url));
  }

  if (session && isPublicRoute) {
    // If logged in and on a public route, redirect to dashboard
    return NextResponse.redirect(new URL('/', req.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!_next/static|_next/image|favicon.ico).*)',
  ],
}
