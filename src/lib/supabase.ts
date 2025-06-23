
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

let supabase: SupabaseClient | null = null;
if (supabaseUrl && supabaseAnonKey) {
    supabase = createClient(supabaseUrl, supabaseAnonKey);
} else {
    console.warn('[Supabase Client] NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY are not set. Client-side database features will be unavailable.');
}

let supabaseAdmin: SupabaseClient | null = null;
if (supabaseUrl && supabaseServiceRoleKey) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: { persistSession: false },
    });
} else {
     // Throw an error in production, but allow to continue for local dev with mocks
     if (process.env.NODE_ENV === 'production') {
        throw new Error('[Supabase Admin] SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for server-side operations.');
     }
     console.warn('[Supabase Admin] SUPABASE_SERVICE_ROLE_KEY is not set. Admin database features will not work, and the app will rely on mock data.');
}

export const isSupabaseClientEnabled = !!supabase;
export const isSupabaseAdminEnabled = !!supabaseAdmin;
export { supabase, supabaseAdmin };
