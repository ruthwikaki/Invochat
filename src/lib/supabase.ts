
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

if (!supabaseUrl || !supabaseAnonKey) {
    console.warn('[Supabase] Client-side environment variables are not set. Database features may be unavailable.');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!supabaseServiceRoleKey) {
     console.warn('[Supabase] Service role key is not set. Admin database operations will fail.');
}

// For server-side with service role, bypassing RLS
export const supabaseAdmin = createClient(
  supabaseUrl,
  supabaseServiceRoleKey
);
