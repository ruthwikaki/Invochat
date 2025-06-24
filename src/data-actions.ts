
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

async function getCompanyIdForCurrentUser(): Promise<string> {
    const SUPABASE_CONFIGURED = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

    if (!SUPABASE_CONFIGURED) {
        throw new Error("Database is not configured. Please set Supabase environment variables.");
    }
    
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
        console.error(`User ${user.id} is missing a valid company_id in app_metadata. This is usually set by a database trigger.`);
        throw new Error("Your user account is not associated with a company. Please contact support.");
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
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    return { success: false, count: null, error: 'Supabase service role credentials are not configured.' };
  }

  try {
    const companyId = await getCompanyIdForCurrentUser();
    
    const serviceSupabase = createServiceRoleClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false }
    });

    const { error, count } = await serviceSupabase
      .from('inventory')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId);

    if (error) {
      throw error;
    }

    return { success: true, count: count, error: null };

  } catch (e: any) {
    let errorMessage = e.message;
    if (e.message.includes('Your user account is not associated with a company')) {
        errorMessage = "Could not find a company ID for the logged-in user. The test query cannot be performed."
    }
    return { success: false, count: null, error: errorMessage };
  }
}
