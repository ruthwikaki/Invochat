
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { logger } from '../logger';

// A private, module-level variable to cache the client instance.
// It starts as null and will be populated on the first call to getServiceRoleClient.
let supabaseAdmin: SupabaseClient | null = null;

/**
 * Returns the Supabase admin client. It uses lazy initialization to create the client
 * on the first call, preventing startup crashes if environment variables are missing.
 * This function should only be called after the environment has been validated.
 *
 * @throws {Error} If the required Supabase environment variables are not set.
 */
export function getServiceRoleClient(): SupabaseClient {
  // If the client has already been created, return the cached instance.
  if (supabaseAdmin) {
    return supabaseAdmin;
  }

  // Startup validation is now handled centrally in src/config/app-config.ts and the root layout.
  // This check is a safeguard.
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServiceRoleKey) {
    // This error will now be caught by the application's error boundaries
    // because it's thrown during a request, not at startup.
    throw new Error('Database admin client is not configured. Critical environment variables (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY) are missing.');
  }
  
  // Create, cache, and return the client instance.
  supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
          autoRefreshToken: false,
          persistSession: false
      }
  });

  logger.info('[Supabase Admin] Lazily initialized Supabase admin client.');

  return supabaseAdmin;
}
