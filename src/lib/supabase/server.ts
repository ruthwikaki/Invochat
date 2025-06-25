
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'

// This function is now DEPRECATED and will be removed.
// The Supabase client should be created directly in the server-side
// file that needs it (e.g., middleware, server actions) to ensure the
// correct cookie-handling context is provided.
// This file is kept to avoid breaking imports, but it should not be used.
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
