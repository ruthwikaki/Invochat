
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { envValidation } from '@/config/app-config';
import type { Database } from '@/types/database.types';

export function createServerSupabaseClient() {
  const cookieStore = cookies()

  if (!envValidation.success) {
     const errorMessage = `Supabase admin client cannot be initialized due to missing environment variables.`;
     throw new Error(errorMessage);
  }

  return createServerClient<Database>(
    envValidation.data.NEXT_PUBLIC_SUPABASE_URL,
    envValidation.data.SUPABASE_SERVICE_ROLE_KEY,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value, ...options })
          } catch (error) {
            // The `set` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
        remove(name: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value: '', ...options })
          } catch (error) {
            // The `delete` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
      },
    }
  )
}
