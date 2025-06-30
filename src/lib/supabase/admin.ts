import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../logger';

// Startup validation is now handled centrally in src/config/app-config.ts.
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

let supabaseAdmin: SupabaseClient | null = null;

// This initialization still runs, but the app will not start if the keys are missing
// due to the new validation in app-config.ts.
if (supabaseUrl && supabaseServiceRoleKey) {
    supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: {
            autoRefreshToken: false,
            persistSession: false
        }
    });
} else {
    // This warning is now less critical because the app won't start if keys are missing,
    // but it is kept as a fallback safeguard.
    logger.warn(`[Supabase Admin] Supabase admin client is not configured. Admin operations will fail. Please set NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your environment.`);
}

/**
 * Returns the Supabase admin client and throws a clear error if it's not configured.
 * This is the single source of truth for getting the admin client.
 */
export function getServiceRoleClient(): SupabaseClient {
    if (!supabaseAdmin) {
        // This error should theoretically not be reachable if the startup validation passes,
        // but it's a crucial runtime check to prevent hard-to-debug null pointer exceptions.
        throw new Error('Database admin client is not configured. This should have been caught at startup. Please check server logs.');
    }
    return supabaseAdmin;
}
