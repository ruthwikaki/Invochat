

import { createServerClient as createServerClientOriginal, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { envValidation, config } from '@/config/app-config';
import type { Database } from '@/types/database.types';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';


let supabaseAdmin: SupabaseClient<Database> | null = null;
let supabaseAdminError: string | null = null;

if (envValidation.success) {
    if (envValidation.data.SUPABASE_URL && envValidation.data.SUPABASE_SERVICE_ROLE_KEY) {
        supabaseAdmin = createClient<Database>(
            envValidation.data.SUPABASE_URL,
            envValidation.data.SUPABASE_SERVICE_ROLE_KEY,
            {
                auth: {
                    autoRefreshToken: false,
                    persistSession: false
                },
                global: {
                    fetch: (url, options = {}) => {
                        const signal = AbortSignal.timeout(config.database.queryTimeout);
                        return fetch(url, { ...options, signal });
                    }
                }
            }
        );
    } else {
        supabaseAdminError = 'Supabase URL or Service Role Key is missing from environment variables.';
        console.warn(`[Supabase Admin] ${supabaseAdminError}`);
    }
} else {
    supabaseAdminError = `Supabase admin client cannot be initialized due to missing environment variables: ${JSON.stringify(envValidation.error.flatten().fieldErrors)}`;
    console.warn(`[Supabase Admin] ${supabaseAdminError}`);
}


export function getServiceRoleClient(): SupabaseClient<Database> {
  if (!supabaseAdmin) {
    throw new Error(supabaseAdminError || 'Supabase admin client not initialized');
  }
  return supabaseAdmin;
}

// Re-export createServerClient for use in server components/actions
export function createServerClient() {
  const cookieStore = cookies()

  if (!envValidation.success) {
     const errorMessage = `Supabase admin client cannot be initialized due to missing environment variables.`;
     throw new Error(errorMessage);
  }

  return createServerClientOriginal<Database>(
    envValidation.data.NEXT_PUBLIC_SUPABASE_URL,
    envValidation.data.NEXT_PUBLIC_SUPABASE_ANON_KEY,
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
          }
        },
        remove(name: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value: '', ...options })
          } catch (error) {
            // The `delete` method was called from a Server Component.
          }
        },
      },
    }
  )
}
