


'use server';

import { createServerClient } from '@/lib/supabase/admin';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { User } from '@/types';
import { logError } from './error-handler';
import { retry } from './async-utils';
import { logger } from '@/lib/logger';

/**
 * Gets the current authenticated user from the server-side context.
 * This is the canonical way to get the user in Server Components and Server Actions.
 * @returns The current user object or null if not authenticated.
 */
export async function getCurrentUser(): Promise<User | null> {
  const supabase = createServerClient();
  const { data: { user }, error: _error } = await supabase.auth.getUser();
  
  if (_error) {
    // In a server context, it's better to log and return null than to throw.
    logError(_error, { context: "Error fetching current user in auth-helpers" });
    return null;
  }
  return user as User | null;
}

/**
 * Helper function to get company ID from database with retry logic.
 * This function will poll the database if the company ID is not immediately available.
 */
async function getCompanyIdFromDatabase(userId: string): Promise<string | null> {
    const serviceSupabase = getServiceRoleClient();
    
    try {
        return await retry(async () => {
            const { data, error } = await serviceSupabase
                .from('company_users')
                .select('company_id')
                .eq('user_id', userId)
                .single();
            
            if (error) {
                // If no rows are found, it's a valid retry case, otherwise throw.
                if (error.code === 'PGRST116') {
                    throw new Error(`Company association not yet found for user ${userId}. Retrying...`);
                }
                throw new Error(`Database query failed: ${error.message}`);
            }
            
            if (!data?.company_id) {
                throw new Error(`Company association not yet found in database for user ${userId}.`);
            }
            
            return data.company_id;
        }, { 
            maxAttempts: 5, 
            delayMs: 300,
            onRetry: (e, attempt) => logger.debug(`getCompanyIdFromDatabase retry attempt ${attempt} for user ${userId}: ${e.message}`)
        });
    } catch(e) {
        logError(e, { context: 'getCompanyIdFromDatabase failed after all retries.', userId });
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
    
    let companyId = user.app_metadata.company_id;
    
    // If companyId is not in the JWT metadata, poll the database with retries.
    // This handles the small delay between user creation and the trigger populating the data.
    if (!companyId) {
        companyId = await getCompanyIdFromDatabase(user.id);
    }
    
    if (!companyId) {
        logError(new Error("No company association found for user."), { 
            context: 'getAuthContext authorization failure',
            userId: user.id,
            userEmail: user.email,
        });
        
        throw new Error("Authorization failed: User is not associated with a company.");
    }

    return { userId: user.id, companyId };
}


/**
 * Enhanced function for debugging auth issues during development
 */
export async function debugAuthContext() {
    if (process.env.NODE_ENV === 'production') {
        return { error: 'Debug function not available in production' };
    }
    
    const supabase = createServerClient();
    const { data: { user } } = await supabase.auth.getUser();
    
    if (!user) {
        return { error: 'No user found' };
    }
    
    const serviceSupabase = getServiceRoleClient();
    
    const { data: companyData, error: companyError } = await serviceSupabase
        .from('company_users')
        .select('*')
        .eq('user_id', user.id);
    
    const { data: companiesData, error: companiesError } = await serviceSupabase
        .from('companies')
        .select('*')
        .eq('owner_id', user.id);
    
    return {
        user: {
            id: user.id,
            email: user.email,
            app_metadata: user.app_metadata,
            user_metadata: user.user_metadata
        },
        companyUsers: { data: companyData, error: companyError },
        companies: { data: companiesData, error: companiesError }
    };
}
