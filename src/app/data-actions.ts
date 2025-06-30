
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB,
    getDatabaseSchemaAndData as getDbSchemaAndData,
    getCompanySettings as getSettings,
    updateCompanySettings as updateSettingsInDb,
    generateAnomalyInsights as getAnomalyInsightsFromDB,
    getUnifiedInventoryFromDB,
    getInventoryCategoriesFromDB,
    getTeamMembersFromDB,
    inviteUserToCompany as inviteUserToCompanyInDb,
    removeTeamMemberFromDb,
    updateTeamMemberRoleInDb,
} from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { User, CompanySettings, UnifiedInventoryItem, TeamMember } from '@/types';
import { ai } from '@/ai/genkit';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { invalidateCompanyCache } from '@/lib/redis';
import { revalidatePath } from 'next/cache';
import { validateCSRFToken, CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';

// This function provides a robust way to get the company ID for the current user.
// It is now designed to be crash-proof. It throws an error if any issue occurs.
async function getAuthContext(): Promise<{ userId: string, companyId: string }> {
    logger.debug('[getAuthContext] Attempting to determine Company ID...');
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
            logger.error('[getCompanyIdForCurrentUser] Supabase auth error:', error.message);
            throw new Error(`Authentication error: ${error.message}`);
        }

        // Check app_metadata first (set by trigger), then user_metadata as a fallback (set on signup).
        const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
        
        if (!user || !companyId || typeof companyId !== 'string') {
            logger.warn('[getCompanyIdForCurrentUser] Could not determine Company ID. User may not be fully signed up or session is invalid.');
            throw new Error('Your user session is invalid or not fully configured. Please try signing out and signing back in.');
        }
        
        logger.debug(`[getCompanyIdForCurrentUser] Success. Company ID: ${companyId}`);
        return { userId: user.id, companyId };
    } catch (e) {
        logError(e, { context: 'getAuthContext' });
        // Re-throw the error to be caught by the calling function's error boundary.
        throw e;
    }
}


export async function getDashboardData(dateRange: string = '30d') {
    try {
        const { companyId } = await getAuthContext();
        return getDashboardMetrics(companyId, dateRange);
    } catch (error) {
        logError(error, { context: 'getDashboardData' });
        // Re-throw the error so the calling page's error boundary can catch it.
        throw error;
    }
}

export async function getUnifiedInventory(params: { query?: string; category?: string }): Promise<UnifiedInventoryItem[]> {
    const { companyId } = await getAuthContext();
    return getUnifiedInventoryFromDB(companyId, params);
}

export async function getInventoryCategories(): Promise<string[]> {
    const { companyId } = await getAuthContext();
    return getInventoryCategoriesFromDB(companyId);
}

export async function getDeadStockData() {
    const { companyId } = await getAuthContext();
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const { companyId } = await getAuthContext();
    return getSuppliersFromDB(companyId);
}

export async function getAlertsData() {
    const { companyId } = await getAuthContext();
    return getAlertsFromDB(companyId);
}

export async function getDatabaseSchemaAndData() {
    const { companyId } = await getAuthContext();
    return getDbSchemaAndData(companyId);
}

export async function getCompanySettings(): Promise<CompanySettings> {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function getAnomalyInsights() {
    const { companyId } = await getAuthContext();
    return getAnomalyInsightsFromDB(companyId);
}


// Zod schema for validating company settings updates.
const CompanySettingsUpdateSchema = z.object({
    dead_stock_days: z.number().int().positive('Dead stock days must be a positive number.'),
    fast_moving_days: z.number().int().positive('Fast-moving days must be a positive number.'),
    overstock_multiplier: z.number().positive('Overstock multiplier must be a positive number.'),
    high_value_threshold: z.number().int().positive('High-value threshold must be a positive number.'),
    currency: z.string().nullable().optional(),
    timezone: z.string().nullable().optional(),
    tax_rate: z.number().nullable().optional(),
    theme_primary_color: z.string().nullable().optional(),
    theme_background_color: z.string().nullable().optional(),
    theme_accent_color: z.string().nullable().optional(),
});


export async function updateCompanySettings(settings: Partial<CompanySettings>): Promise<CompanySettings> {
    const parsedSettings = CompanySettingsUpdateSchema.safeParse(settings);
    
    if (!parsedSettings.success) {
        const errorMessages = parsedSettings.error.issues.map(issue => issue.message).join(' ');
        throw new Error(`Invalid settings format: ${errorMessages}`);
    }

    const { companyId } = await getAuthContext();
    // Exclude company_id and other non-updatable fields from the payload
    const { company_id, created_at, updated_at, ...updateData } = settings;
    return updateSettingsInDb(companyId, updateData);
}

export async function getTeamMembers(): Promise<TeamMember[]> {
    const { companyId } = await getAuthContext();
    const members = await getTeamMembersFromDB(companyId);

    return members.map(member => ({
        id: member.id,
        email: member.email,
        role: member.role as TeamMember['role'],
    }));
}

const InviteTeamMemberSchema = z.object({
  email: z.string().email({ message: "Please enter a valid email address." }),
});

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const cookieStore = cookies();
        const csrfTokenFromCookie = cookieStore.get(CSRF_COOKIE_NAME)?.value;
        const csrfTokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;

        if (!csrfTokenFromCookie || !csrfTokenFromForm || !validateCSRFToken(csrfTokenFromForm, csrfTokenFromCookie)) {
            logger.warn(`[CSRF] Invalid token for invite team member action.`);
            return { success: false, error: 'Invalid form submission. Please try again.' };
        }

        const parsed = InviteTeamMemberSchema.safeParse({ email: formData.get('email') });
        if (!parsed.success) {
            return { success: false, error: parsed.error.issues[0].message };
        }
        const { email } = parsed.data;

        const { userId, companyId } = await getAuthContext();
        const supabase = getServiceRoleClient();

        // RBAC Check: Ensure the current user has permission to invite.
        const { data: currentUserData, error: roleError } = await supabase
            .from('users')
            .select('role')
            .eq('id', userId)
            .single();

        if (roleError || !currentUserData) throw new Error("Could not verify your permissions.");
        if (currentUserData.role !== 'Owner' && currentUserData.role !== 'Admin') {
            return { success: false, error: "You do not have permission to invite users." };
        }
        
        const { data: companyData, error: companyError } = await supabase
            .from('companies')
            .select('name')
            .eq('id', companyId)
            .single();

        if (companyError || !companyData) {
            throw new Error('Could not retrieve company information to send invite.');
        }

        await inviteUserToCompanyInDb(companyId, companyData.name, email);
        revalidatePath('/settings/team');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'inviteTeamMember' });
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function testSupabaseConnection(): Promise<{
    success: boolean;
    error: { message: string; details?: unknown; } | null;
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

    } catch (e) {
        return { success: false, error: { message: getErrorMessage(e), details: e }, user: null, isConfigured };
    }
}

// Corrected to use service_role key to bypass RLS for a raw table count.
export async function testDatabaseQuery(): Promise<{
  success: boolean;
  count: number | null;
  error: string | null;
}> {
  try {
    const { companyId } = await getAuthContext();
    
    const serviceSupabase = getServiceRoleClient();

    // Test a table that is guaranteed to exist for any configured company
    const { error, count } = await serviceSupabase
      .from('company_settings')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId);

    if (error) throw error;

    return { success: true, count: count, error: null };
  } catch (e) {
    // If getCompanyId throws, its error message is more informative.
    let errorMessage = getErrorMessage(e);
    if (errorMessage?.includes('database')) { // Supabase-specific error
        errorMessage = `Database query failed: ${errorMessage}`;
    } else if (errorMessage?.includes('relation "public.company_settings" does not exist')) {
        errorMessage = "Database query failed: The 'company_settings' table could not be found. Please ensure your database schema is set up correctly by running the SQL in the setup page.";
    }
    return { success: false, count: null, error: errorMessage };
  }
}


export async function testMaterializedView(): Promise<{ success: boolean; error: string | null; }> {
    try {
        const serviceSupabase = getServiceRoleClient();

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
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
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
        const model = config.ai.model;
        
        await ai.generate({
            model: model,
            prompt: 'Test prompt: say "hello".',
            config: {
                temperature: 0.1,
            }
        });

        return { success: true, error: null, isConfigured };
    } catch (e) {
        const errorMessage = getErrorMessage(e);
        let detailedMessage = errorMessage;

        if ((e as { status?: string })?.status === 'NOT_FOUND' || errorMessage?.includes('NOT_FOUND') || errorMessage?.includes('Model not found')) {
            detailedMessage = `The configured AI model ('${config.ai.model}') is not available. This is often due to the "Generative Language API" not being enabled in your Google Cloud project, or the project is missing a billing account.`;
        } else if (errorMessage?.includes('API key not valid')) {
            detailedMessage = 'Your Google AI API key is invalid. Please check the `GOOGLE_API_KEY` in your `.env` file.'
        }
        return { success: false, error: detailedMessage, isConfigured };
    }
}

export async function testRedisConnection(): Promise<{
    success: boolean;
    error: string | null;
    isEnabled: boolean;
}> {
    if (!isRedisEnabled) {
        return { success: true, error: 'Redis is not configured (REDIS_URL is not set), so caching and rate limiting are disabled. This is not a failure.', isEnabled: false };
    }
    try {
        const pong = await redisClient.ping();
        if (pong !== 'PONG') {
            throw new Error('Redis PING command did not return PONG.');
        }
        return { success: true, error: null, isEnabled: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e), isEnabled: true };
    }
}

export async function removeTeamMember(memberIdToRemove: string): Promise<{ success: boolean; error?: string }> {
    try {
        const { userId: currentUserId, companyId } = await getAuthContext();

        // Security check: You cannot remove yourself.
        if (memberIdToRemove === currentUserId) {
            return { success: false, error: "You cannot remove yourself from the team." };
        }

        // RBAC Check: Ensure the current user has permission to remove members.
        const supabase = getServiceRoleClient();
        const { data: currentUserData, error: roleError } = await supabase
            .from('users')
            .select('role')
            .eq('id', currentUserId)
            .single();

        if (roleError || !currentUserData) throw new Error("Could not verify your permissions.");
        if (currentUserData.role !== 'Owner' && currentUserData.role !== 'Admin') {
            return { success: false, error: "You do not have permission to remove team members." };
        }

        const result = await removeTeamMemberFromDb(memberIdToRemove, companyId);
        
        if (result.success) {
            logger.info(`[Remove Action] Successfully removed user ${memberIdToRemove} by user ${currentUserId}`);
            revalidatePath('/settings/team');
        } else {
             logger.error(`[Remove Action] Failed to remove team member ${memberIdToRemove}:`, result.error);
        }
        
        return result;

    } catch (e) {
        logError(e, { context: 'removeTeamMember' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateTeamMemberRole(memberIdToUpdate: string, newRole: 'Admin' | 'Member'): Promise<{ success: boolean; error?: string }> {
    try {
        const { userId: currentUserId, companyId } = await getAuthContext();

        // Security Check 1: Get the current user's role from the database.
        const supabase = getServiceRoleClient();
        const { data: currentUserData, error: currentUserError } = await supabase
            .from('users')
            .select('role')
            .eq('id', currentUserId)
            .single();

        if (currentUserError || !currentUserData) {
            throw new Error("Could not verify your permissions.");
        }
        
        // Security Check 2: Only owners can change roles.
        if (currentUserData.role !== 'Owner') {
            return { success: false, error: "You do not have permission to change user roles." };
        }
        
        // Security Check 3: You cannot change the Owner's role.
        const { data: memberToUpdateData, error: memberToUpdateError } = await supabase
            .from('users')
            .select('role')
            .eq('id', memberIdToUpdate)
            .single();
            
        if (memberToUpdateError || !memberToUpdateData) {
            throw new Error("The specified user was not found.");
        }

        if (memberToUpdateData.role === 'Owner') {
            return { success: false, error: "The company owner's role cannot be changed." };
        }
        
        // Update the user's role in the database.
        const result = await updateTeamMemberRoleInDb(memberIdToUpdate, companyId, newRole);

        if (result.success) {
             logger.info(`[Role Update] User ${currentUserId} updated role for ${memberIdToUpdate} to ${newRole}`);
             revalidatePath('/settings/team');
        } else {
            logger.error(`[Role Update Action] Failed to update role for ${memberIdToUpdate}:`, result.error);
        }
       
        return result;

    } catch (e) {
        logError(e, { context: 'updateTeamMemberRole' });
        return { success: false, error: getErrorMessage(e) };
    }
}
