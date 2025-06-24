
import { createBrowserClient } from '@supabase/ssr'

export function createBrowserSupabaseClient() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    // This client is used in the browser, so we can't throw an error here.
    // The AuthProvider will handle showing an error message to the user.
    return null;
  }
  
  // Create a supabase client on the browser with project's credentials
  return createBrowserClient(supabaseUrl, supabaseAnonKey);
}
