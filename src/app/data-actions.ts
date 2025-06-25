
'use server';

import { createClient } from '@/lib/supabase/server';
import { createClient as createServiceRoleClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getInventoryItems, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB
} from '@/services/database';
import type { User } from '@/types';

// This function provides a robust way to get the company ID for the current user.
// It prioritizes the JWT claim for performance and security, with a fallback to a direct DB query.
async function getCompanyIdForCurrentUser(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
        throw new Error("User not found. Please log in again.");
    }

    // The company_id should be in the user's JWT `app_metadata` set by the database trigger.
    // This is the fastest, most reliable source.
    const companyIdFromClaim = user.app_metadata?.company_id;
    if (companyIdFromClaim && typeof companyIdFromClaim === 'string') {
        return companyIdFromClaim;
    }

    // Fallback: If the claim is missing (e.g., JWT not refreshed yet), query the public.users table.
    // This adds robustness but should not be the primary method.
    console.warn(`User ${user.id} is missing company_id in JWT claim. Falling back to DB query. This may indicate an issue with the handle_new_user trigger.`);
    
    const { data: profile } = await supabase
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .single();
        
    const companyIdFromDb = profile?.company_id;
    if (companyIdFromDb) {
        return companyIdFromDb;
    }

    // If both methods fail, it is a critical configuration error.
    console.error(`CRITICAL: User ${user.id} has no company_id in JWT or users table.`);
    throw new Error("Your user account is not associated with a company. Please ensure the `handle_new_user` database trigger is installed and working correctly.");
}


export async function getDashboardData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDashboardMetrics(companyId);
}

export async function getInventoryData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getInventoryItems(companyId);
}

export async function getDeadStockData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getSuppliersFromDB(companyId);
}

export async function getAlertsData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getAlertsFromDB(companyId);
}

export async function testSupabaseConnection(): Promise<{
    success: boolean;
    error: { message: string; details?: any; } | null;
    user: User | null;
    isConfigured: boolean;
}> {
    const isConfigured = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

    if (!isConfigured) {
        return {
            success: false,
            error: { message: 'Supabase environment variables (NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY) are not set.' },
            user: null,
            isConfigured,
        };
    }
    
    try {
        const cookieStore = cookies();
        const supabase = createClient(cookieStore);
        const { data: { user }, error } = await supabase.auth.getUser();

        if (error) {
            // AuthSessionMissingError is not a "real" error in this context, it just means no one is logged in.
            if (error.name === 'AuthSessionMissingError') {
                 return { success: true, error: null, user: null, isConfigured };
            }
            return { success: false, error: { message: error.message, details: error }, user: null, isConfigured };
        }
        
        return { success: true, error: null, user, isConfigured };

    } catch (e: any) {
        return { success: false, error: { message: e.message, details: e }, user: null, isConfigured };
    }
}

// Corrected to use service_role key to bypass RLS for a raw table count.
export async function testDatabaseQuery(): Promise<{
  success: boolean;
  count: number | null;
  error: string | null;
}> {
  try {
    const companyId = await getCompanyIdForCurrentUser();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceKey) {
        return { success: false, count: null, error: 'Supabase service role credentials are not configured on the server.' };
    }

    // Create a client with the service_role key to bypass RLS for this test.
    const serviceSupabase = createServiceRoleClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false }
    });

    const { error, count } = await serviceSupabase
      .from('inventory')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId);

    if (error) throw error;

    return { success: true, count: count, error: null };
  } catch (e: any) {
    let errorMessage = e.message;
    if (e.message?.includes('User not found')) {
        errorMessage = "Could not find a logged-in user to get a company ID for the test query."
    }
    return { success: false, count: null, error: errorMessage };
  }
}
