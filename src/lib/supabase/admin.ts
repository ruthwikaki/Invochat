import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../logger';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

let supabaseAdmin: SupabaseClient | null = null;

if (supabaseUrl && supabaseServiceRoleKey) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: {
            autoRefreshToken: false,
            persistSession: false
        }
    });
} else {
    logger.warn(`[Supabase Admin] Supabase admin client is not configured. Admin operations will fail. Please set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your environment.`);
}

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 * This is the single source of truth for getting the admin client.
 */
export function getServiceRoleClient(): SupabaseClient {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. Please ensure SUPABASE_SERVICE_ROLE_KEY is set in your environment variables.');
    }
    return supabaseAdmin;
}
