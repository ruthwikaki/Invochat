
import { createServerClient as createClientPrimitive, type CookieOptions } from '@supabase/ssr'
import { type cookies } from 'next/headers'

export function createClient(cookieStore: ReturnType<typeof cookies>) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    // In a server component, this will stop rendering and show the error boundary.
    // This is better than crashing the server process.
    throw new Error('Missing Supabase credentials in environment variables.');
  }

  return createClientPrimitive(
    supabaseUrl,
    supabaseAnonKey,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          // A Server Action should always be able to set cookies.
          // If this throws an error, it's a real bug that needs to be fixed.
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          // A Server Action should always be able to set cookies.
          // If this throws an error, it's a real bug that needs to be fixed.
          cookieStore.set({ name, value: '', ...options })
        },
      },
    }
  )
}
