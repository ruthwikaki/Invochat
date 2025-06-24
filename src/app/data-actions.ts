
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

    // The company_id is stored in the user's app_metadata, which is set by a trigger in Supabase.
    const companyId = user.app_metadata?.company_id;

    if (!companyId || typeof companyId !== 'string') {
        // This is a critical error state. It means the user exists but is not properly associated with a company.
        // This can happen in a race condition right after signup. The trigger might not have completed.
        // We now have a fallback in the UI/error boundary to handle this.
        console.error(`User ${user.id} is missing a valid company_id in app_metadata. This is usually set by a database trigger.`);
        throw new Error("Your user account is not yet associated with a company. This can take a moment after signup. Please try refreshing the page.");
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
            // This can happen if the cookie is invalid or expired. It's not a config error.
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
  const isConfigured = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
  if (!isConfigured) {
    return { success: false, count: null, error: 'Supabase credentials are not configured.' };
  }

  try {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    
    // Check if user is logged in first
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
        return { success: false, count: null, error: "No authenticated user session found. Please log in." };
    }
    
    // The RLS policies will handle scoping this to the user's company
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
