
import { createBrowserClient } from '@supabase/ssr'
import type { SupabaseClient } from '@supabase/supabase-js';

// This function creates a Supabase client for use in the browser.
// It's a singleton pattern, wrapped in a function to ensure environment
// variables are available before the client is created.
export function createBrowserSupabaseClient(): SupabaseClient {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
