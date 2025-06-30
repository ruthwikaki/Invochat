import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../logger';

// Startup validation is now handled centrally in src/config/app-config.ts and the root layout.
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
    // This warning is a fallback. The main error handling is in layout.tsx.
    logger.warn(`[Supabase Admin] Supabase admin client is not configured because environment variables are missing.`);
}

/**
 * Returns the Supabase admin client. Throws an error if it's not configured.
 * This function should only be called after the environment has been validated by the root layout.
 */
export function getServiceRoleClient(): SupabaseClient {
    if (!supabaseAdmin) {
        throw new Error('Database admin client is not configured. This indicates the application tried to access the database before environment validation passed. Please check server logs.');
    }
    return supabaseAdmin;
}
