
import { createClientComponentClient } from '@supabase/auth-helpers-nextjs';
import type { SupabaseClient } from '@supabase/supabase-js';

// This function creates a Supabase client for use in the browser.
// It's a singleton pattern, wrapped in a function to ensure environment
// variables are available before the client is created.
export function createBrowserSupabaseClient(): SupabaseClient {
  return createClientComponentClient();
}
