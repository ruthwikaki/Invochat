
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
// It relies on the middleware to ensure that the user session is valid and contains a company ID.
async function getCompanyIdForCurrentUser(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    const { data: { user } } = await supabase.auth.getUser();

    // The middleware should prevent this function from being called by a user
    // without a company_id. If this error is thrown, it's a bug in the middleware.
    const companyId = user?.app_metadata?.company_id;
    if (!user || !companyId || typeof companyId !== 'string') {
        throw new Error("Application error: Could not determine company ID. The user may not be properly authenticated or configured.");
    }
    
    return companyId;
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
    // Catch the specific error from getCompanyIdForCurrentUser if it's called for a user without a session
    if (e.message?.includes('Application error')) {
        errorMessage = "Could not perform database query test: " + e.message;
    } else if (e.message?.includes('User not found')) {
        errorMessage = "Could not find a logged-in user to get a company ID for the test query."
    }
    return { success: false, count: null, error: errorMessage };
  }
}
