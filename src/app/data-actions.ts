
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

    // First, try to get company_id from the users table (most reliable with RLS)
    const { data: userRecord, error } = await supabase
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .single();

    if (!error && userRecord?.company_id) {
        return userRecord.company_id;
    }

    // Fallback: Check app_metadata (might not work with RLS)
    const companyId = user.app_metadata?.company_id;
    if (companyId && typeof companyId === 'string') {
        return companyId;
    }

    // Log detailed error for debugging
    console.error(`User ${user.id} has no company_id. User record:`, userRecord, 'Error:', error);
    
    // Better error message
    throw new Error("Your account is not associated with a company. This usually happens right after signup. Please try refreshing the page or contact support if the issue persists.");
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
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);

    // RLS will automatically scope the query to the user's company
    const { error, count } = await supabase
      .from('inventory')
      .select('*', { count: 'exact', head: true });

    if (error) {
      // If RLS is enforced and company_id is missing, this will fail.
      // We can check for a specific error if needed, but for now, just bubble it up.
      throw error;
    }

    return { success: true, count: count, error: null };
  } catch (e: any) {
    return { success: false, count: null, error: e.message };
  }
}
