import { NextResponse, type NextRequest } from 'next/server';
import { createServerClient, type CookieOptions } from '@supabase/ssr';

export async function middleware(req: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return req.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          // Set cookie on the request object
          req.cookies.set({
            name,
            value,
            ...options,
          });
          // Set cookie on the response object
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({
            name,
            value,
            ...options,
          });
        },
        remove(name: string, options: CookieOptions) {
          // Remove cookie from request object
          req.cookies.delete(name);
          // Remove cookie from response object
          response = NextResponse.next({
            request: {
              headers: req.headers,
            },
          });
          response.cookies.set({
            name,
            value: '',
            ...options,
            maxAge: 0,
          });
        },
      },
    }
  );

  const { pathname } = req.nextUrl;
  const authRoutes = ['/login', '/signup'];
  const publicRoutes = ['/quick-test'];
  const isAuthRoute = authRoutes.includes(pathname);
  const isPublicRoute = publicRoutes.includes(pathname);

  try {
    // IMPORTANT: Use getUser() instead of getSession() for more reliable auth check
    const { data: { user }, error } = await supabase.auth.getUser();

    if (error) {
      console.error('[Middleware] Auth error:', error);
    }

    // If user is authenticated
    if (user) {
      if (isAuthRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
      if (pathname === '/') {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }

      const companyId = user.app_metadata?.company_id;
      const isSetupIncompleteRoute = pathname === '/setup-incomplete';

      if (!companyId && !isSetupIncompleteRoute) {
        if (pathname !== '/test-supabase' && pathname !== '/quick-test') {
          return NextResponse.redirect(new URL('/setup-incomplete', req.url));
        }
      }

      if (companyId && isSetupIncompleteRoute) {
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
    } else {
      // If user is not authenticated and trying to access a protected route
      if (!isAuthRoute && !isPublicRoute) {
        return NextResponse.redirect(new URL('/login', req.url));
      }
    }
  } catch (error) {
    console.error('[Middleware] Error:', error);
    // On error, allow access to auth routes but protect others
    if (!isAuthRoute && !isPublicRoute) {
      return NextResponse.redirect(new URL('/login', req.url));
    }
  }
  
  return response;
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public|api).*)'],
};