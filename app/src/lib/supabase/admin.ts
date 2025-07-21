
'use server';

import { createServerClient as createServerClientOriginal, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { envValidation } from '@/config/app-config';
import type { Database } from '@/types/database.types';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';


let supabaseAdmin: SupabaseClient<Database> | null = null;

export function getServiceRoleClient(): SupabaseClient<Database> {
  if (supabaseAdmin) {
    return supabaseAdmin;
  }

  if (!envValidation.success) {
     const errorDetails = envValidation.error.flatten().fieldErrors;
     const errorMessage = `Supabase admin client cannot be initialized due to missing environment variables: ${JSON.stringify(errorDetails)}`;
     throw new Error(errorMessage);
  }
  
  supabaseAdmin = createClient<Database>(
      envValidation.data.SUPABASE_URL, 
      envValidation.data.SUPABASE_SERVICE_ROLE_KEY, 
      {
          auth: {
              autoRefreshToken: false,
              persistSession: false
          }
      }
  );

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

