
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(req: NextRequest) {
  console.log('🔍 MIDDLEWARE START - Path:', req.nextUrl.pathname);
  
  // Check environment variables
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  
  console.log('🔑 Environment check:', {
    hasUrl: !!supabaseUrl,
    hasAnonKey: !!supabaseAnonKey,
    urlPreview: supabaseUrl ? supabaseUrl.substring(0, 20) + '...' : 'MISSING'
  });

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('❌ Missing Supabase environment variables');
    return NextResponse.redirect(new URL('/login', req.url));
  }

  // Create a response object that we can modify and return
  let res = NextResponse.next({
    request: {
      headers: req.headers,
    },
  });

  // Log existing cookies
  console.log('🍪 Existing cookies:', req.cookies.getAll().map(c => c.name));

  // Create a Supabase client that can read/write cookies
  const supabase = createServerClient(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        get(name: string) {
          const value = req.cookies.get(name)?.value;
          console.log(`🍪 GET cookie ${name}:`, value ? 'EXISTS' : 'MISSING');
          return value;
        },
        set(name: string, value: string, options: CookieOptions) {
          console.log(`🍪 SET cookie ${name}`);
          req.cookies.set({ name, value, ...options });
          res.cookies.set({ name, value, ...options });
        },
        remove(name: string, options: CookieOptions) {
          console.log(`🍪 REMOVE cookie ${name}`);
          req.cookies.set({ name, value: '', ...options });
          res.cookies.set({ name, value: '', ...options });
        },
      },
    }
  );

  try {
    // IMPORTANT: This call will refresh the session if it's expired.
    const { data: { session }, error } = await supabase.auth.getSession();
    
    console.log('🔐 Session check:', {
      hasSession: !!session,
      hasUser: !!session?.user,
      userId: session?.user?.id,
      userEmail: session?.user?.email,
      error: error?.message
    });

    if (error) {
      console.error('❌ Session error:', error);
    }
    
    const user = session?.user;
    const { pathname } = req.nextUrl;
    
    const authRoutes = ['/login', '/signup'];
    const isAuthRoute = authRoutes.includes(pathname);
    const isSetupIncompleteRoute = pathname === '/setup-incomplete';

    console.log('📍 Route analysis:', {
      pathname,
      isAuthRoute,
      isSetupIncompleteRoute,
      hasUser: !!user
    });

    // Handle the root path ('/')
    if (pathname === '/') {
      const redirectTo = user ? '/dashboard' : '/login';
      console.log('🏠 Root redirect to:', redirectTo);
      return NextResponse.redirect(new URL(redirectTo, req.url));
    }

    // If the user is not logged in, protect all routes except for auth and setup pages.
    if (!user) {
      if (!isAuthRoute && !isSetupIncompleteRoute) {
        console.log('🚫 No user, redirecting to login from:', pathname);
        return NextResponse.redirect(new URL('/login', req.url));
      }
      console.log('✅ No user but on allowed route, continuing');
      return res;
    }
    
    // If the user is logged in, handle redirects away from auth pages
    // and check if their account setup is complete.
    const companyId = user.app_metadata?.company_id;
    
    console.log('👤 User metadata:', {
      userId: user.id,
      email: user.email,
      hasCompanyId: !!companyId,
      companyId: companyId,
      appMetadata: user.app_metadata
    });

    if (isAuthRoute) {
      console.log('🔄 Authenticated user on auth route, redirecting to dashboard');
      return NextResponse.redirect(new URL('/dashboard', req.url));
    }

    // If the user is missing a company_id, send them to the setup page.
    if (!companyId) {
      if (!isSetupIncompleteRoute) {
        console.log('⚠️ No company_id, redirecting to setup');
        return NextResponse.redirect(new URL('/setup-incomplete', req.url));
      }
      console.log('✅ No company_id but on setup page, continuing');
    } else {
      // If the user has a company_id but is on the setup page, send them to the dashboard.
      if (isSetupIncompleteRoute) {
        console.log('🔄 Has company_id but on setup page, redirecting to dashboard');
        return NextResponse.redirect(new URL('/dashboard', req.url));
      }
    }

    // All checks have passed, so return the response with the potentially updated session cookie.
    console.log('✅ All checks passed, allowing access to:', pathname);
    return res;
    
  } catch (error) {
    console.error('💥 Middleware error:', error);
    return NextResponse.redirect(new URL('/login', req.url));
  }
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
