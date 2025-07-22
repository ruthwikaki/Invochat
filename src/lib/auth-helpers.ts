
import { createBrowserClient } from '@supabase/ssr';
import { SupabaseClient } from '@supabase/supabase-js';

let supabase: SupabaseClient;

function getSupabase() {
    if (!supabase) {
        supabase = createBrowserClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
        );
    }
    return supabase;
}

export async function getCurrentUser() {
  const supabase = getSupabase();
  const { data: { user }, error } = await supabase.auth.getUser();
  
  if (error) throw error;
  return user;
}

export async function getCurrentCompanyId(): Promise<string | null> {
  const user = await getCurrentUser();
  return user?.app_metadata?.company_id || null;
}

    