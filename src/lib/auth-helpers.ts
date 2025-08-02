
'use server';

import { createServerClient } from '@/lib/supabase/admin';
import { getServiceRoleClient } from '@/lib/supabase/admin'; // ADD THIS IMPORT
import type { User } from '@/types';
import { logError } from './error-handler';
import { retry } from './async-utils';

/**
 * Gets the current authenticated user from the server-side context.
 * This is the canonical way to get the user in Server Components and Server Actions.
 * @returns The current user object or null if not authenticated.
 */
export async function getCurrentUser(): Promise<User | null> {
  const supabase = createServerClient();
  const { data: { user }, error } = await supabase.auth.getUser();
  
  if (error) {
    // In a server context, it's better to log and return null than to throw.
    logError(error, { context: "Error fetching current user in auth-helpers" });
    return null;
  }
  return user as User | null;
}

/**
 * Gets the company ID for the current user.
 * @returns The company ID (UUID string) or null if not found.
 */
export async function getCurrentCompanyId(): Promise<string | null> {
  const user = await getCurrentUser();
  if (!user) return null;
  
  // The JWT is the primary source of truth.
  const companyIdFromJWT = user?.app_metadata?.company_id;
  if (companyIdFromJWT) {
    return companyIdFromJWT;
  }
  
  // The database trigger should prevent this, but as a fallback, check the DB.
  logError(new Error("JWT missing company_id, attempting DB fallback."), { userId: user.id });
  return await getCompanyIdFromDatabase(user.id);
}

/**
 * Helper function to get company ID from database with retry logic
 * FIXED: Now uses service role client to bypass RLS policies
 */
async function getCompanyIdFromDatabase(userId: string): Promise<string | null> {
    // CRITICAL FIX: Use service role client instead of regular client
    const serviceSupabase = getServiceRoleClient(); // CHANGED FROM createServerClient()
    
    try {
        return await retry(async () => {
            const { data: companyUserData, error } = await serviceSupabase // USING SERVICE ROLE CLIENT
                .from('company_users')
                .select('company_id')
                .eq('user_id', userId)
                .single();
            
            if (error) {
                // Throw to trigger a retry
                throw new Error(`Fallback DB check failed for user ${userId}: ${error.message}`);
            }
            if (!companyUserData?.company_id) {
                // Throw to trigger a retry, as the record may not have been created yet
                throw new Error(`Company association not yet found in database for user ${userId}.`);
            }
            return companyUserData.company_id;
        }, { 
            maxAttempts: 3, 
            delayMs: 300,
            onRetry: (e, attempt) => logError(e, { context: `getCompanyIdFromDatabase fallback retry attempt ${attempt}` })
        });
    } catch(e) {
        logError(e, { context: 'getCompanyIdFromDatabase failed after all retries.' });
        return null; // Return null if all retries fail
    }
}


/**
 * A helper function to get the full authentication context (user and company ID)
 * in a single call. Throws an error if the user is not authenticated.
 * @returns An object containing the userId and companyId.
 * @throws {Error} if the user is not authenticated or a company ID cannot be found.
 */
export async function getAuthContext() {
    const supabase = createServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) {
        throw new Error("Authentication required: No user session found.");
    }
    
    // The company_id from the JWT's app_metadata is the primary source of truth.
    // The new database trigger makes this highly reliable.
    let companyId = user.app_metadata.company_id;
    
    // If, for some reason (extreme race condition), the JWT is not updated,
    // we have a simple, robust fallback.
    if (!companyId) {
        companyId = await getCompanyIdFromDatabase(user.id);
    }
    
    if (!companyId) {
        // If after all checks there is no company ID, authorization fails.
        logError(new Error("No company association found"), { 
            context: 'getAuthContext: Complete failure',
            userId: user.id,
            userEmail: user.email,
        });
        
        throw new Error("Authorization failed: User is not associated with a company.");
    }

    return { userId: user.id, companyId };
}


/**
 * Enhanced function for debugging auth issues during development
 * FIXED: Now uses service role client to avoid RLS issues
 */
export async function debugAuthContext() {
    if (process.env.NODE_ENV === 'production') {
        return { error: 'Debug function not available in production' };
    }
    
    const supabase = createServerClient();
    const { data: { user }, error } = await supabase.auth.getUser();
    
    if (!user) {
        return { error: 'No user found' };
    }
    
    // FIXED: Use service role client for debugging to bypass RLS
    const serviceSupabase = getServiceRoleClient();
    
    // Check company_users table
    const { data: companyData, error: companyError } = await serviceSupabase // USING SERVICE ROLE
        .from('company_users')
        .select('*')
        .eq('user_id', user.id);
    
    // Check companies table
    const { data: companiesData, error: companiesError } = await serviceSupabase // USING SERVICE ROLE
        .from('companies')
        .select('*')
        .eq('owner_id', user.id);
    
    return {
        user: {
            id: user.id,
            email: user.email,
            app_metadata: user.app_metadata,
            raw_user_meta_data: user.raw_user_meta_data
        },
        companyUsers: { data: companyData, error: companyError },
        companies: { data: companiesData, error: companiesError }
    };
}
