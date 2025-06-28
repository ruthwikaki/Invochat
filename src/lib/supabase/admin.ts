
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../logger';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

let supabaseAdmin: SupabaseClient | null = null;
let isSupabaseAdminEnabled = false;
let supabaseAdminError: string | null = null;


if (supabaseUrl && supabaseServiceRoleKey) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: {
            autoRefreshToken: false,
            persistSession: false
        }
    });
    isSupabaseAdminEnabled = true;
} else {
    supabaseAdminError = 'Supabase admin client is not configured. Admin operations will fail. Please set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your environment.';
    logger.warn(`[Supabase Admin] ${supabaseAdminError}`);
}

export { supabaseAdmin, isSupabaseAdminEnabled, supabaseAdminError };
