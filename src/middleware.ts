
import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => req.cookies.get(name)?.value,
        set: (name, value, options) => res.cookies.set({ name, value, ...options }),
        remove: (name, options) => res.cookies.set({ name, value: '', ...options }),
      },
    }
  );

  const {
    data: { session },
  } = await supabase.auth.getSession();

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const publicRoutes = ['/quick-test'];

  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  if (!session && !isAuthRoute && !isPublicRoute) {
    return NextResponse.redirect(new URL('/login', req.url));
  }

  if (session) {
    if (isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
    if (pathname === '/') {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }

    const companyId = session.user.app_metadata?.company_id;
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    if (!companyId && !isSetupIncompleteRoute) {
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    }

    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  return res;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)'],
};
