import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // If no Supabase credentials, allow access to login/signup only
  if (!supabaseUrl || !supabaseAnonKey) {
    const { pathname } = request.nextUrl;
    
    // Allow access to auth routes and static files
    if (pathname.startsWith('/login') || 
        pathname.startsWith('/signup') || 
        pathname.startsWith('/_next') ||
        pathname === '/') {
      return response;
    }
    
    // Redirect to login for any other route
    return NextResponse.redirect(new URL('/login', request.url));
  }

  try {
    const supabase = createServerClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        cookies: {
          get(name: string) {
            return request.cookies.get(name)?.value
          },
          set(name: string, value: string, options: CookieOptions) {
            // Set cookie on both request and response
            request.cookies.set({ name, value, ...options })
            response = NextResponse.next({
              request: {
                headers: request.headers,
              },
            })
            response.cookies.set({ name, value, ...options })
          },
          remove(name: string, options: CookieOptions) {
            // Remove cookie from both request and response
            request.cookies.set({ name, value: '', ...options })
            response = NextResponse.next({
              request: {
                headers: request.headers,
              },
            })
            response.cookies.set({ name, value: '', ...options })
          },
        },
      }
    );

    // Get user session
    const { data: { user }, error } = await supabase.auth.getUser();
    
    if (error) {
      console.error('Middleware auth error:', error);
    }

    const { pathname } = request.nextUrl;

    // Define route types
    const protectedRoutes = ['/dashboard', '/chat', '/inventory', '/import', '/dead-stock', '/suppliers', '/analytics', '/alerts'];
    const authRoutes = ['/login', '/signup'];
    
    const isProtectedRoute = protectedRoutes.some(route => pathname.startsWith(route));
    const isAuthRoute = authRoutes.some(route => pathname.startsWith(route));

    // Redirect logic
    if (!user && isProtectedRoute) {
      const url = new URL('/login', request.url);
      url.searchParams.set('redirectTo', pathname);
      return NextResponse.redirect(url);
    }

    if (user && isAuthRoute) {
      return NextResponse.redirect(new URL('/dashboard', request.url));
    }
    
    // Root redirect
    if (pathname === '/') {
      return NextResponse.redirect(new URL(user ? '/dashboard' : '/login', request.url));
    }

  } catch (error) {
    console.error('Middleware error:', error);
    // On error, allow access to auth routes only
    const { pathname } = request.nextUrl;
    if (!pathname.startsWith('/login') && !pathname.startsWith('/signup')) {
      return NextResponse.redirect(new URL('/login', request.url));
    }
  }

  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - api (API routes)
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - public files (images, etc)
     */
    '/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
