
import { createBrowserClient } from '@supabase/ssr'
import type { SupabaseClient } from '@supabase/supabase-js';

export function createBrowserSupabaseClient(): SupabaseClient | null {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('Missing Supabase environment variables. App will be in a degraded state.');
    return null;
  }
  
  try {
    // Create a supabase client on the browser with project's credentials
    return createBrowserClient(
      supabaseUrl,
      supabaseAnonKey
    );
  } catch (error) {
    console.error('Failed to create Supabase client:', error);
    // In a real app, you might want to show a global error UI
    return null;
  }
}
