
import { createBrowserClient } from '@supabase/ssr'

export function createBrowserSupabaseClient(url: string, anonKey: string) {
  // Create a supabase client on the browser with project's credentials
  return createBrowserClient(url, anonKey);
}
