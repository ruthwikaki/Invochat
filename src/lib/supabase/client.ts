
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

// This function is intended to be called from client components.
// It will only ever create one instance of the client.
export function createBrowserSupabaseClient(): SupabaseClient {
  // The client needs the NEXT_PUBLIC_ variables to be available.
  // These are now securely managed and validated before the app starts.
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
