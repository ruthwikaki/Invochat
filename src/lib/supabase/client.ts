
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

// This function is intended to be called from client components.
// It will only ever create one instance of the client.
export function createBrowserSupabaseClient(): SupabaseClient {
  // The client needs the NEXT_PUBLIC_ variables to be available.
  // These are now securely managed and validated before the app starts.
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
      throw new Error("Supabase URL or anonymous key is not configured in client environment.");
  }
  
  return createBrowserClient(
    supabaseUrl,
    supabaseAnonKey
  );
}
