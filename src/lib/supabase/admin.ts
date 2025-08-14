
import { createServerClient as createServerClientOriginal, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { config } from '@/config/app-config';
import type { Database } from '@/types/database.types';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let supabaseAdmin: SupabaseClient<Database> | null = null;

function getSupabaseAdmin() {
    if (supabaseAdmin) {
        return supabaseAdmin;
    }

    // Use fallback values if validation failed but env vars exist
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    
    if (!supabaseUrl || !serviceRoleKey) {
        throw new Error('Supabase URL or Service Role Key is missing from environment variables for admin client.');
    }

    supabaseAdmin = createClient<Database>(
        supabaseUrl,
        serviceRoleKey,
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
    return getSupabaseAdmin();
}

export function createServerClient() {
    const cookieStore = cookies()

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !anonKey) {
        throw new Error('Supabase URL or Anon Key is missing from environment variables.');
    }

    return createServerClientOriginal<Database>(
        supabaseUrl,
        anonKey,
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
