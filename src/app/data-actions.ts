
'use server';

import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { createClient as createServiceRoleClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getProductsData, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB,
    getDatabaseSchemaAndData as getDbSchemaAndData,
    getCompanySettings as getSettings,
    updateCompanySettings as updateSettings,
} from '@/services/database';
import type { User, CompanySettings } from '@/types';
import { ai } from '@/ai/genkit';
import { APP_CONFIG } from '@/config/app-config';

// This function provides a robust way to get the company ID for the current user.
// It is now designed to be crash-proof. It throws an error if any issue occurs.
async function getCompanyIdForCurrentUser(): Promise<string> {
    console.log('[getCompanyIdForCurrentUser] Attempting to determine Company ID...');
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
            throw new Error(`Authentication error: ${error.message}`);
        }

        // Check app_metadata first (set by trigger), then user_metadata as a fallback (set on signup).
        const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
        
        if (!user || !companyId || typeof companyId !== 'string') {
            console.warn('[getCompanyIdForCurrentUser] Could not determine Company ID. User may not be fully signed up or session is invalid.');
            throw new Error('Your user session is invalid or not fully configured. Please try signing out and signing back in.');
        }
        
        console.log(`[getCompanyIdForCurrentUser] Success. Company ID: ${companyId}`);
        return companyId;
    } catch (e: any) {
        console.error('[getCompanyIdForCurrentUser] Caught exception:', e.message);
        // Re-throw the error to be caught by the calling function's error boundary.
        throw e;
    }
}


export async function getDashboardData() {
    try {
        const companyId = await getCompanyIdForCurrentUser();
        return getDashboardMetrics(companyId);
    } catch (error) {
        console.error('[Data Action Error] Failed to get dashboard data:', error);
        // Re-throw the error so the calling page's error boundary can catch it.
        throw error;
    }
}

export async function getInventoryData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getProductsData(companyId);
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

export async function getDatabaseSchemaAndData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDbSchemaAndData(companyId);
}

export async function getCompanySettings(): Promise<CompanySettings> {
    const companyId = await getCompanyIdForCurrentUser();
    return getSettings(companyId);
}

export async function updateCompanySettings(settings: Partial<Omit<CompanySettings, 'company_id'>>): Promise<CompanySettings> {
    const companyId = await getCompanyIdForCurrentUser();
    return updateSettings(companyId, settings);
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
    
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceKey) {
        return { success: false, count: null, error: 'Supabase service role credentials are not configured on the server.' };
    }

    // Create a client with the service_role key to bypass RLS for this test.
    const serviceSupabase = createServiceRoleClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false }
    });

    // Test a table that is confirmed to exist, like 'vendors'.
    const { error, count } = await serviceSupabase
      .from('vendors')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId);

    if (error) throw error;

    return { success: true, count: count, error: null };
  } catch (e: any) {
    // If getCompanyId throws, its error message is more informative.
    let errorMessage = e.message;
    if (e.message?.includes('database')) { // Supabase-specific error
        errorMessage = `Database query failed: ${e.message}`;
    } else if (e.message?.includes('relation "public.vendors" does not exist')) {
        errorMessage = "Database query failed: The 'vendors' table could not be found. Please ensure your database schema is set up correctly.";
    }
    return { success: false, count: null, error: errorMessage };
  }
}


export async function testMaterializedView(): Promise<{ success: boolean; error: string | null; }> {
    try {
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
        const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

        if (!supabaseUrl || !supabaseServiceKey) {
            return { success: false, error: 'Supabase service role credentials are not configured on the server.' };
        }
        const serviceSupabase = createServiceRoleClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false } });

        const { data, error } = await serviceSupabase
            .from('pg_matviews')
            .select('matviewname')
            .eq('matviewname', 'company_dashboard_metrics')
            .single();

        if (error) {
            // If it's a 'no rows returned' error, it means the view doesn't exist.
            if (error.code === 'PGRST116') {
                return { success: false, error: 'The `company_dashboard_metrics` materialized view is missing. Run the setup SQL for better performance.' };
            }
            throw error; // For other unexpected errors
        }

        return { success: !!data, error: null };
    } catch(e: any) {
        return { success: false, error: e.message };
    }
}


export async function testGenkitConnection(): Promise<{
    success: boolean;
    error: string | null;
    isConfigured: boolean;
}> {
    const isConfigured = !!process.env.GOOGLE_API_KEY;

    if (!isConfigured) {
        return {
            success: false,
            error: 'Genkit is not configured. GOOGLE_API_KEY environment variable is not set.',
            isConfigured,
        };
    }

    try {
        // Use the model from the app config for an accurate test
        const model = APP_CONFIG.ai.model;
        
        await ai.generate({
            model: model,
            prompt: 'Test prompt: say "hello".',
            config: {
                temperature: 0.1,
            }
        });

        return { success: true, error: null, isConfigured };
    } catch (e: any) {
        let errorMessage = e.message || 'An unknown error occurred.';
        if (e.status === 'NOT_FOUND' || e.message?.includes('NOT_FOUND') || e.message?.includes('Model not found')) {
            errorMessage = `The configured AI model ('${APP_CONFIG.ai.model}') is not available. This is often due to the "Generative Language API" not being enabled in your Google Cloud project, or the project is missing a billing account.`;
        } else if (e.message?.includes('API key not valid')) {
            errorMessage = 'Your Google AI API key is invalid. Please check the `GOOGLE_API_KEY` in your `.env` file.'
        }
        return { success: false, error: errorMessage, isConfigured };
    }
}
