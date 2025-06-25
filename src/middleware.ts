
import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  // Create a single response object up front that we can mutate.
  const res = NextResponse.next();

  // Create a Supabase client that can read and write cookies to the response.
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

  // This will refresh the session if it's expired and update the cookies.
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

    // If setup is incomplete (no companyId), redirect to the setup page.
    if (!companyId && !isSetupIncompleteRoute) {
      // Allow access to test pages even if setup is incomplete
      if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
    }

    // If setup IS complete, but they somehow land on the setup page, redirect them away.
    if (companyId && isSetupIncompleteRoute) {
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }
  }

  // Return the response object, which may have new cookies set.
  return res;
}

export const config = {
  matcher: [ '/((?!_next/static|_next/image|favicon.ico|api|_vercel|public).*)' ],
};
