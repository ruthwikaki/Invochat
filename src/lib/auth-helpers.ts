
'use server';

import { createServerClient } from '@/lib/supabase/admin';
import type { User } from '@/types';
import { logError } from './error-handler';

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
  return user?.app_metadata?.company_id || null;
}

/**
 * A helper function to get the full authentication context (user and company ID)
 * in a single call. Throws an error if the user is not authenticated.
 * This function includes a database fallback to prevent race conditions during signup
 * where the JWT's app_metadata may not yet be updated.
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
    // check the database directly. This is the source of truth, but it's slower.
    if (!companyId) {
        const { data: companyUserData, error } = await supabase
            .from('company_users')
            .select('company_id')
            .eq('user_id', user.id)
            .single();

        if (error) {
             logError(error, { context: 'getAuthContext: Fallback DB check for company_id failed.'});
             throw new Error("Authorization failed: Could not verify user's company association.");
        }
        
        companyId = companyUserData?.company_id;
    }
    
    if (!companyId) {
        // If, after both checks, there is still no company ID, then the user is
        // not properly set up. The middleware will handle redirecting this user.
        throw new Error("Authorization failed: User is not associated with a company.");
    }

    return { userId: user.id, companyId };
}
