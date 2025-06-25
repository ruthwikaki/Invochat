
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'

// This function creates a Supabase client for use in Server Components,
// Server Actions, and Route Handlers. It's essential for server-side
// logic that needs to interact with Supabase while respecting RLS.
export function createClient(cookieStore: ReturnType<typeof cookies>) {
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // The `set` method is called by the Supabase client when it needs
          // to persist the session to a cookie. This is essential for
          // Server Actions, which are the only place cookies can be set.
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          // The `remove` method is called by the Supabase client when it needs
          // to clear the session cookie.
          cookieStore.set({ name, value: '', ...options })
        },
      },
    }
  )
}
