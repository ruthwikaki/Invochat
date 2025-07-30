
import { createServerClient as createServerClientOriginal, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { config, envValidation } from '@/config/app-config';
import type { Database } from '@/types/database.types';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';


let supabaseAdmin: SupabaseClient<Database> | null = null;

// This function is now responsible for initializing the admin client.
// It is only ever called on the server, ensuring the service key is never in a client-accessible scope.
function getSupabaseAdmin() {
    if (supabaseAdmin) {
        return supabaseAdmin;
    }

    if (!envValidation.success) {
        throw new Error('Supabase admin client cannot be initialized due to missing environment variables.');
    }
    
    if (!envValidation.data.NEXT_PUBLIC_SUPABASE_URL || !envValidation.data.SUPABASE_SERVICE_ROLE_KEY) {
        throw new Error('Supabase URL or Service Role Key is missing from environment variables for admin client.');
    }

    supabaseAdmin = createClient<Database>(
        envValidation.data.NEXT_PUBLIC_SUPABASE_URL,
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
    
    return supabaseAdmin;
}


export function getServiceRoleClient(): SupabaseClient<Database> {
  // Lazily initialize the client on first use.
  return getSupabaseAdmin();
}

// Re-export createServerClient for use in server components/actions
export function createServerClient() {
  const cookieStore = cookies()

  if (!envValidation.success) {
     const errorMessage = `Supabase client cannot be initialized due to missing environment variables.`;
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
