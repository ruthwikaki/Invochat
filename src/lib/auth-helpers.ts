
'use server';

import { createServerClient } from '@/lib/supabase/admin';
import type { User } from '@/types';
import { logError } from './error-handler';
import { getErrorMessage } from './error-handler';
import { retry, delay } from './async-utils';

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
  
  // Try JWT first
  const companyIdFromJWT = user?.app_metadata?.company_id;
  if (companyIdFromJWT) {
    return companyIdFromJWT;
  }
  
  // Fallback to database with retry logic
  return await getCompanyIdFromDatabase(user.id);
}

/**
 * Helper function to get company ID from database with retry logic
 */
async function getCompanyIdFromDatabase(userId: string): Promise<string | null> {
  const supabase = createServerClient();
  let retries = 3;
  let delayMs = 100; // Start with 100ms delay

  while (retries > 0) {
    try {
      const { data: companyUserData, error } = await supabase
        .from('company_users')
        .select('company_id')
        .eq('user_id', userId)
        .single();

      if (!error && companyUserData?.company_id) {
        return companyUserData.company_id;
      }

      if (error && error.code !== 'PGRST116') { // PGRST116 is "no rows returned"
        logError(error, { 
          context: 'getCompanyIdFromDatabase', 
          userId,
          attempt: 4 - retries 
        });
      }

      // If this is not the last retry, wait before trying again
      if (retries > 1) {
        await new Promise(resolve => setTimeout(resolve, delayMs));
        delayMs *= 2; // Exponential backoff
      }

    } catch (e) {
      logError(e, { 
        context: 'getCompanyIdFromDatabase exception', 
        userId,
        attempt: 4 - retries 
      });
    }

    retries--;
  }

  return null;
}

/**
 * A helper function to get the full authentication context (user and company ID)
 * in a single call. Throws an error if the user is not authenticated.
 * This function includes a database fallback with retry logic to handle race conditions.
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
    // It's fast and doesn't require an extra database hit.
    let companyId = user.app_metadata.company_id;
    
    // Fallback for race condition on signup: If company_id is not in the JWT metadata,
    // check the database directly with retry logic.
    if (!companyId) {
        logError(new Error("JWT missing company_id, attempting DB fallback."), { userId: user.id });
        try {
            companyId = await retry(async () => {
                const { data: companyUserData, error } = await supabase
                    .from('company_users')
                    .select('company_id')
                    .eq('user_id', user.id)
                    .single();
                
                if (error) {
                    throw new Error(`Fallback DB check failed: ${error.message}`);
                }
                if (!companyUserData?.company_id) {
                    throw new Error("Company association not yet found in database.");
                }
                
                return companyUserData.company_id;
            }, { 
                maxAttempts: 3, 
                delayMs: 500,
                onRetry: (e, attempt) => logError(e, { context: `getAuthContext fallback retry attempt ${attempt}` })
            });

        } catch (e) {
            logError(e, { context: 'getAuthContext: Fallback DB check failed after multiple retries.'});
            throw new Error("Authorization failed: Could not verify user's company association after multiple attempts.");
        }
    }
    
    if (!companyId) {
        // If, after both checks, there is still no company ID, then the user is
        // not properly set up. The middleware will handle redirecting this user.
        throw new Error("Authorization failed: User is not associated with a company.");
    }

    return { userId: user.id, companyId };
}

/**
 * Enhanced function for debugging auth issues during development
 * Remove this in production
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
    
    // Check company_users table
    const { data: companyData, error: companyError } = await supabase
        .from('company_users')
        .select('*')
        .eq('user_id', user.id);
    
    // Check companies table
    const { data: companiesData, error: companiesError } = await supabase
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
