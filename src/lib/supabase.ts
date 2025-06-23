import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const isSupabaseClientEnabled = !!(supabaseUrl && supabaseAnonKey);
export const isSupabaseAdminEnabled = !!(supabaseUrl && supabaseServiceRoleKey);

let supabase: SupabaseClient | null = null;
if (isSupabaseClientEnabled) {
    supabase = createClient(supabaseUrl, supabaseAnonKey);
} else {
    console.warn('[Supabase] Client-side environment variables are not set. Client-side database features will be unavailable.');
}

let supabaseAdmin: SupabaseClient | null = null;
if (isSupabaseAdminEnabled) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey);
} else {
     console.warn('[Supabase] Admin environment variables are not set. Admin Supabase client is not available. App will use mock data.');
}

export { supabase, supabaseAdmin };
