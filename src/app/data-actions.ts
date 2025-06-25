
'use server';

import { createClient } from '@/lib/supabase/server';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getInventoryItems, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB
} from '@/services/database';
import type { User } from '@/types';

async function getCompanyIdForCurrentUser(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
        throw new Error("User not found. Please log in again.");
    }

    // The company_id is stored in the user's app_metadata (JWT claim).
    // This is the fastest, most reliable source once the session is established.
    const companyIdFromClaim = user.app_metadata?.company_id;
    if (companyIdFromClaim && typeof companyIdFromClaim === 'string') {
        return companyIdFromClaim;
    }

    // This is a critical error state if the trigger is working correctly.
    // However, we can add a fallback for robustness.
    console.warn(`User ${user.id} is missing company_id in JWT claim. Falling back to DB query.`);
    
    // Fallback: Query the public.users table directly.
    // This is slower but can save a user if the JWT is slow to update.
    const { data: profile } = await supabase
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .single();
        
    const companyIdFromDb = profile?.company_id;
    if (companyIdFromDb) {
        return companyIdFromDb;
    }

    // If both methods fail, it's a critical error.
    console.error(`User ${user.id} is missing a valid company_id in both JWT claims and the users table.`);
    throw new Error("I couldn't verify your company information. This might be a temporary issue after signup. Please try logging out and in again.");
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
            if (error.name === 'AuthSessionMissingError') {
                 return {
                    success: true,
                    error: null,
                    user: null,
                    isConfigured
                };
            }
            
            return {
                success: false,
                error: { message: 'An unexpected error occurred while fetching the user.', details: error },
                user: null,
                isConfigured
            };
        }
        
        return {
            success: true,
            error: null,
            user,
            isConfigured
        };

    } catch (e: any) {
        return {
            success: false,
            error: { message: 'A server-side error occurred while trying to connect to Supabase.', details: e.message },
            user: null,
            isConfigured
        };
    }
}

export async function testDatabaseQuery(): Promise<{
  success: boolean;
  count: number | null;
  error: string | null;
}> {
  try {
    const companyId = await getCompanyIdForCurrentUser(); // This will throw if user is not associated
    
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);

    // RLS will automatically scope the query to the user's company
    const { error, count } = await supabase
      .from('inventory')
      .select('*', { count: 'exact', head: true });

    if (error) {
      throw error;
    }

    return { success: true, count: count, error: null };
  } catch (e: any) {
    return { success: false, count: null, error: e.message };
  }
}
