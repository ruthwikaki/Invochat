
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
 * in a single call. Throws an error if the user is not authenticated, making it
 * suitable for protecting server actions.
 * This now performs a database check to ensure the user actually belongs to the company.
 * @returns An object containing the userId and companyId.
 * @throws {Error} if the user is not authenticated, does not have a company ID, or is not a valid member of that company.
 */
export async function getAuthContext() {
    const supabase = createServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) {
        throw new Error("Authentication required: No user session found.");
    }
    
    const companyId = user.app_metadata.company_id;
    
    if (!companyId) {
        throw new Error("Authorization failed: User is not associated with a company.");
    }

    // CRITICAL: Verify from the database that the user is actually a member of the company.
    // This prevents any potential issues if the JWT metadata were to become stale or be manipulated.
    const { data: companyUser, error } = await supabase
        .from('company_users')
        .select('user_id')
        .eq('user_id', user.id)
        .eq('company_id', companyId)
        .single();
    
    if (error || !companyUser) {
        logError(error, { context: 'getAuthContext company membership validation failed', userId: user.id, companyId });
        throw new Error("Authorization failed: User is not a valid member of the specified company.");
    }

    return { userId: user.id, companyId };
}
