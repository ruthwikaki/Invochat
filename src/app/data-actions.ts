
'use server';

import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { createClient as createServiceRoleClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getInventoryItems, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB,
    getDatabaseSchemaAndData as getDbSchemaAndData
} from '@/services/database';
import type { User } from '@/types';

// This function provides a robust way to get the company ID for the current user.
// It is now designed to be crash-proof. It returns null if any issue occurs.
async function getCompanyIdForCurrentUser(): Promise<string | null> {
    try {
        const cookieStore = cookies();
        const supabase = createServerClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL!,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
          {
            cookies: {
              get(name: string) {
                return cookieStore.get(name)?.value;
              },
            },
          }
        );
        const { data: { user }, error } = await supabase.auth.getUser();

        if (error) {
            console.error('[getCompanyIdForCurrentUser] Supabase auth error:', error.message);
            return null;
        }

        // Check app_metadata first (set by trigger), then user_metadata as a fallback (set on signup).
        const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
        
        if (!user || !companyId || typeof companyId !== 'string') {
            console.warn('[getCompanyIdForCurrentUser] Could not determine company ID. User may not be fully signed up or session is invalid.');
            return null;
        }
        
        return companyId;
    } catch (e: any) {
        console.error('[getCompanyIdForCurrentUser] Caught exception:', e.message);
        return null;
    }
}


export async function getDashboardData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return { inventoryValue: 0, deadStockValue: 0, lowStockCount: 0, totalSKUs: 0, totalSuppliers: 0, totalSalesValue: 0 };
    }
    return getDashboardMetrics(companyId);
}

export async function getInventoryData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return [];
    }
    return getInventoryItems(companyId);
}

export async function getDeadStockData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return { deadStock: [], totalValue: 0, totalUnits: 0, averageAge: 0 };
    }
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return [];
    }
    return getSuppliersFromDB(companyId);
}

export async function getAlertsData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return [];
    }
    return getAlertsFromDB(companyId);
}

export async function getDatabaseSchemaAndData() {
    const companyId = await getCompanyIdForCurrentUser();
    if (!companyId) {
        return [];
    }
    return getDbSchemaAndData(companyId);
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
        const supabase = createServerClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            {
                cookies: {
                    get(name: string) {
                        return cookieStore.get(name)?.value;
                    },
                },
            }
        );
        const { data: { user }, error } = await supabase.auth.getUser();

        if (error) {
            // AuthError is not a "real" error in this context, it just means no one is logged in.
            if (error.name === 'AuthError') {
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
    if (!companyId) {
        return { success: false, count: null, error: 'Could not determine company ID for the test query. User might not be logged in or there was a connection issue.' };
    }
    
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
    return { success: false, count: null, error: e.message };
  }
}
