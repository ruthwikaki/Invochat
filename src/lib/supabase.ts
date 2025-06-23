
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

let supabase: SupabaseClient | null = null;
let supabaseError: string | null = null;

if (supabaseUrl && supabaseAnonKey) {
    supabase = createClient(supabaseUrl, supabaseAnonKey);
} else {
    supabaseError = 'Supabase client is not configured. Database features will be unavailable. Please set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY in your environment.';
    console.warn(`[Supabase] ${supabaseError}`);
}

/**
 * A Supabase client instance. May be null if environment variables are not set.
 */
export { supabase, supabaseError };
