'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import * as db from '@/services/database';
import type { User, CompanySettings, UnifiedInventoryItem, TeamMember, Anomaly, PurchaseOrder, PurchaseOrderCreateInput, ReorderSuggestion, ReceiveItemsFormInput, PurchaseOrderUpdateInput, ChannelFee, Location, LocationFormData, SupplierFormData, Supplier, InventoryUpdateData, SupplierPerformanceReport, InventoryLedgerEntry, Alert, DeadStockItem, ExportJob, Customer, CustomerAnalytics } from '@/types';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { PurchaseOrderCreateSchema, PurchaseOrderUpdateSchema, InventoryUpdateSchema } from '@/types';
import { sendPurchaseOrderEmail, sendEmailAlert } from '@/services/email';
import { redirect } from 'next/navigation';
import type { Integration } from '@/features/integrations/types';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { generateAnomalyExplanation } from '@/ai/flows/anomaly-explanation-flow';
import { ai } from '@/ai/genkit';
import { isRedisEnabled, redisClient, invalidateCompanyCache, rateLimit } from '@/lib/redis';
import { config } from '@/config/app-config';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { validateCSRF, CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';

type UserRole = 'Owner' | 'Admin' | 'Member';

// This function provides a robust way to get the company ID and role for the current user.
// It throws an error if any issue occurs, which is caught by error boundaries.
async function getAuthContext(): Promise<{ userId: string, companyId: string, userRole: UserRole }> {
    logger.debug('[getAuthContext] Attempting to determine Company ID and Role...');
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
            logger.error('[getAuthContext] Supabase auth error:', error.message);
            throw new Error(`Authentication error: ${error.message}`);
        }

        // Check app_metadata first, then fall back to user_metadata for invited users on older system versions
        const companyId = user?.app_metadata?.company_id || user?.user_metadata?.company_id;
        const userRole = user?.app_metadata?.role || user?.user_metadata?.role;
        
        if (!user || !companyId || typeof companyId !== 'string' || !userRole) {
            logger.warn('[getAuthContext] Could not determine Company ID or Role. User may not be fully signed up or session is invalid.');
            throw new Error('Your user session is invalid or not fully configured. Please try signing out and signing back in.');
        }
        
        logger.debug(`[getAuthContext] Success. Company ID: ${companyId}, Role: ${userRole}`);
        return { userId: user.id, companyId, userRole: userRole as UserRole };
    } catch (e) {
        logError(e, { context: 'getAuthContext' });
        // Re-throw the error to be caught by the calling function's error boundary.
        throw e;
    }
}

/**
 * A helper function to enforce Role-Based Access Control.
 * @param currentUserRole The role of the user trying to perform the action.
 * @param allowedRoles An array of roles that are permitted to perform the action.
 * @throws {Error} If the user's role is not in the allowed list.
 */
function requireRole(currentUserRole: UserRole, allowedRoles: UserRole[]) {
    if (!allowedRoles.includes(currentUserRole)) {
        logger.warn(`[RBAC] Access denied for role '${currentUserRole}'. Allowed roles: ${allowedRoles.join(', ')}.`);
        throw new Error('You do not have permission to perform this action.');
    }
}


export async function getDashboardData(dateRange: string = '30d') {
    try {
        const { companyId } = await getAuthContext();
        return db.getDashboardMetrics(companyId, dateRange);
    } catch (error) {
        logError(error, { context: 'getDashboardData' });
        // Re-throw the error so the calling page's error boundary can catch it.
        throw error;
    }
}

export async function getUnifiedInventory(params: { query?: string; category?: string, location?: string, supplier?: string, page?: number, limit?: number }): Promise<{items: UnifiedInventoryItem[], totalCount: number}> {
    const { companyId } = await getAuthContext();
    const limit = params.limit || 50;
    const page = params.page || 1;
    const offset = (page - 1) * limit;

    return db.getUnifiedInventoryFromDB(companyId, { ...params, limit, offset, sku: null });
}

export async function getInventoryCategories(): Promise<string[]> {
    const { companyId } = await getAuthContext();
    return db.getInventoryCategoriesFromDB(companyId);
}

export async function getDeadStockData() {
    const { companyId } = await getAuthContext();
    return db.getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const { companyId } = await getAuthContext();
    return db.getSuppliersFromDB(companyId);
}

const PO_ITEMS_PER_PAGE = 25;
export async function getPurchaseOrders(params: { query?: string, page?: number }): Promise<{ items: PurchaseOrder[], totalCount: number }> {
    const { companyId } = await getAuthContext();
    const limit = PO_ITEMS_PER_PAGE;
    const page = params.page || 1;
    const offset = (page - 1) * limit;
    
    return db.getPurchaseOrdersFromDB(companyId, { query: params.query, limit, offset });
}

export async function getPurchaseOrderById(id: string): Promise<PurchaseOrder | null> {
    const { companyId } = await getAuthContext();
    return db.getPurchaseOrderByIdFromDB(id, companyId);
}

export async function getAlertsData() {
    const { companyId } = await getAuthContext();
    const alerts = await db.getAlertsFromDB(companyId);

    // Simulate sending email alerts for any low stock items found
    const lowStockAlerts = alerts.filter(alert => alert.type === 'low_stock');
    if (lowStockAlerts.length > 0) {
        logger.debug(`[Alerts] Found ${lowStockAlerts.length} low stock alerts. Simulating email notifications.`);
        for (const alert of lowStockAlerts) {
            // In a real app, this would be queued to avoid blocking the request.
            // We use a `catch` here because we don't want a failed email simulation
            // to prevent the user from seeing their alerts in the UI.
            sendEmailAlert(alert).catch(err => {
                logError(err, { context: 'Failed to send simulated email alert' });
            });
        }
    }
    
    return alerts;
}

export async function getDatabaseSchemaAndData() {
    const { companyId } = await getAuthContext();
    return db.getDbSchemaAndData(companyId);
}

export async function getCompanySettings(): Promise<CompanySettings> {
    const { companyId } = await getAuthContext();
    return db.getSettings(companyId);
}

export async function getInsightsPageData(): Promise<{ summary: string; anomalies: Anomaly[]; topDeadStock: DeadStockItem[]; topLowStock: Alert[]; }> {
  try {
    const { companyId } = await getAuthContext();

    // Fetch all data points in parallel
    const [rawAnomalies, deadStockData, alerts] = await Promise.all([
      db.getAnomalyInsightsFromDB(companyId),
      db.getDeadStockPageData(companyId),
      getAlertsData(),
    ]);

    const topDeadStock = deadStockData.deadStockItems
      .sort((a, b) => (b.total_value || 0) - (a.total_value || 0))
      .slice(0, 5);

    const topLowStock = alerts
      .filter(a => a.type === 'low_stock')
      .slice(0, 5);

    // Generate AI explanations for each anomaly
    const explainedAnomalies = await Promise.all(
        rawAnomalies.map(async (anomaly) => {
            try {
                const date = new Date(anomaly.date);
                const explanation = await generateAnomalyExplanation({
                    anomaly: anomaly,
                    dateContext: {
                        dayOfWeek: date.toLocaleDateString('en-US', { weekday: 'long' }),
                        month: date.toLocaleDateString('en-US', { month: 'long' }),
                        season: 'winter', // This would be more dynamic in a real app
                    }
                });
                return { ...anomaly, ...explanation };
            } catch (e) {
                logError(e, { context: `Failed to generate explanation for anomaly on ${anomaly.date}`});
                // Return original anomaly with a default explanation on error
                return { 
                    ...anomaly, 
                    explanation: "AI explanation could not be generated for this anomaly.",
                    confidence: "low",
                    suggestedAction: "Investigate this anomaly manually."
                };
            }
        })
    );
    

    // Generate the summary using the AI flow
    const summary = await generateInsightsSummary({
      anomalies: explainedAnomalies,
      lowStockCount: alerts.filter(a => a.type === 'low_stock').length,
      deadStockCount: deadStockData.deadStockItems.length,
    });
    
    return {
      summary,
      anomalies: explainedAnomalies,
      topDeadStock,
      topLowStock,
    };
  } catch (error) {
    logError(error, { context: 'getInsightsPageData' });
    throw error;
  }
}

export async function updateCompanySettings(formData: FormData): Promise<CompanySettings> {
    const { companyId, userRole } = await getAuthContext();
    requireRole(userRole, ['Owner', 'Admin']);
    const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
    validateCSRF(formData, csrfTokenFromCookie);

    const settings = Object.fromEntries(formData.entries());
    // remove csrf_token from settings object
    delete settings.csrf_token;
    
    return db.updateSettingsInDb(companyId, settings as Partial<CompanySettings>);
}

export async function getTeamMembers(): Promise<TeamMember[]> {
    const { companyId } = await getAuthContext();
    const members = await db.getTeamMembersFromDB(companyId);

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
        const { userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);

        const parsed = InviteTeamMemberSchema.safeParse({ email: formData.get('email') });
        if (!parsed.success) {
            return { success: false, error: parsed.error.issues[0].message };
        }
        const { email } = parsed.data;

        const supabase = getServiceRoleClient();
        
        const { data: companyData, error: companyError } = await supabase
            .from('companies')
            .select('name')
            .eq('id', companyId)
            .single();

        if (companyError || !companyData) {
            throw new Error('Could not retrieve company information to send invite.');
        }

        await db.inviteUserToCompanyInDb(companyId, companyData.name, email);
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

        // This now checks for a regular table instead of a materialized view
        const { data, error } = await serviceSupabase
            .from('company_dashboard_metrics')
            .select('company_id')
            .limit(1);

        if (error) {
            // Check if the error indicates the table doesn't exist
            if (error.code === '42P01') {
                 return { success: false, error: 'The `company_dashboard_metrics` table is missing. Run the setup SQL for better performance.' };
            }
            throw error;
        }

        return { success: true, error: null };
    } catch(e) {
        logError(e, { context: 'testMaterializedView check' });
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

export async function removeTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const memberIdToRemove = formData.get('memberId') as string;
        if (!memberIdToRemove) throw new Error('Member ID is missing.');

        const { userId: currentUserId, userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);

        if (memberIdToRemove === currentUserId) {
            return { success: false, error: "You cannot remove yourself from the team." };
        }

        const result = await db.removeTeamMemberFromDb(memberIdToRemove, companyId, currentUserId);
        
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

export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
     try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const memberIdToUpdate = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as TeamMember['role'];
        if (!memberIdToUpdate || !newRole) throw new Error('Member ID or role is missing.');

        if (!db.isValidUuid(memberIdToUpdate)) throw new Error('Invalid ID format.');
        
        const { userId, userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner']);
        
        const result = await db.updateTeamMemberRoleInDb(memberIdToUpdate, companyId, newRole);

        if (result.success) {
             logger.info(`[Role Update] User role updated for ${memberIdToUpdate} to ${newRole}`);
             revalidatePath('/settings/team');
        } else {
            logger.error(`[Role Update Action] Failed to update role for ${memberIdToUpdate}:`, result.error);
        }
       
        return result;
    } catch(e) {
        logError(e, { context: 'updateTeamMemberRole' });
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function createPurchaseOrder(data: PurchaseOrderCreateInput): Promise<{ success: boolean, error?: string, data?: PurchaseOrder }> {
  const { companyId, userRole } = await getAuthContext();
  requireRole(userRole, ['Owner', 'Admin']);
  const parsedData = PurchaseOrderCreateSchema.safeParse(data);
  if (!parsedData.success) {
    return { success: false, error: "Invalid form data provided." };
  }
  
  try {
    const newPo = await db.createPurchaseOrderInDb(companyId, parsedData.data);
    revalidatePath('/purchase-orders', 'layout');
    return { success: true, data: newPo };
  } catch (e) {
    logError(e, { context: 'createPurchaseOrder action' });
    const message = getErrorMessage(e);
    if (message.includes('unique_po_number_per_company')) {
        return { success: false, error: 'This Purchase Order number already exists. Please use a unique PO number.' };
    }
    return { success: false, error: message };
  }
}

export async function updatePurchaseOrder(poId: string, data: PurchaseOrderUpdateInput): Promise<{ success: boolean, error?: string, data?: PurchaseOrder }> {
  const { companyId, userRole } = await getAuthContext();
  requireRole(userRole, ['Owner', 'Admin']);
  const parsedData = PurchaseOrderUpdateSchema.safeParse(data);
  if (!parsedData.success) {
    return { success: false, error: "Invalid form data provided for update." };
  }

  try {
    await db.updatePurchaseOrderInDb(poId, companyId, parsedData.data);
    revalidatePath('/purchase-orders', 'layout');
    revalidatePath(`/purchase-orders/${poId}`);
    return { success: true };
  } catch (e) {
    logError(e, { context: 'updatePurchaseOrder action' });
    const message = getErrorMessage(e);
    if (message.includes('unique_po_number_per_company')) {
        return { success: false, error: 'This Purchase Order number already exists. Please use a unique PO number.' };
    }
    return { success: false, error: message };
  }
}

export async function deletePurchaseOrder(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const poId = formData.get('poId') as string;
        if (!poId) throw new Error('PO ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.deletePurchaseOrderFromDb(poId, companyId);
        revalidatePath('/purchase-orders', 'layout');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deletePurchaseOrder action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function emailPurchaseOrder(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const poId = formData.get('poId') as string;
        if (!poId) throw new Error('PO ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const purchaseOrder = await db.getPurchaseOrderByIdFromDB(poId, companyId);
        if (!purchaseOrder) {
            return { success: false, error: "Purchase Order not found." };
        }
        if (!purchaseOrder.supplier_email) {
            return { success: false, error: "Supplier does not have an email address on file." };
        }

        await sendPurchaseOrderEmail(purchaseOrder);

        return { success: true };
    } catch (e) {
        logError(e, { context: `emailPurchaseOrder for PO ${poId}`});
        return { success: false, error: getErrorMessage(e) };
    }
}


export async function receivePurchaseOrderItems(data: ReceiveItemsFormInput): Promise<{ success: boolean, error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.receivePurchaseOrderItemsInDB(data.poId, companyId, data.items);
        await db.refreshMaterializedViews(companyId);
        revalidatePath(`/purchase-orders/${data.poId}`);
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'receivePurchaseOrderItems action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getReorderSuggestions(): Promise<ReorderSuggestion[]> {
    const { companyId } = await getAuthContext();
    return db.getReorderSuggestionsFromDB(companyId);
}

export async function createPurchaseOrdersFromSuggestions(
  suggestions: ReorderSuggestion[]
): Promise<{ success: boolean; error?: string; createdPoCount: number }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);

        if (suggestions.length === 0) {
            return { success: false, error: "No suggestions were selected.", createdPoCount: 0 };
        }

        // Group suggestions by supplier
        const groupedBySupplier = suggestions.reduce((acc, suggestion) => {
            const supplierId = suggestion.supplier_id;
            if (!supplierId) return acc; // Skip suggestions with no supplier

            if (!acc[supplierId]) {
                acc[supplierId] = [];
            }
            acc[supplierId].push(suggestion);
            return acc;
        }, {} as Record<string, ReorderSuggestion[]>);


        let createdPoCount = 0;
        for (const supplierId in groupedBySupplier) {
            const supplierSuggestions = groupedBySupplier[supplierId];
            
            const poInput: PurchaseOrderCreateInput = {
                supplier_id: supplierId,
                po_number: `PO-${Date.now()}-${createdPoCount}`,
                order_date: new Date(),
                status: 'draft',
                items: supplierSuggestions.map(s => ({
                    sku: s.sku,
                    quantity_ordered: s.suggested_reorder_quantity,
                    unit_cost: s.unit_cost,
                })),
            };

            await db.createPurchaseOrderInDb(companyId, poInput);
            createdPoCount++;
        }

        revalidatePath('/purchase-orders');
        revalidatePath('/reordering');
        return { success: true, createdPoCount };

    } catch (e) {
        logError(e, { context: 'createPurchaseOrdersFromSuggestions action' });
        return { success: false, error: getErrorMessage(e), createdPoCount: 0 };
    }
}

export async function getChannelFees(): Promise<ChannelFee[]> {
    const { companyId } = await getAuthContext();
    return db.getChannelFeesFromDB(companyId);
}

const UpsertChannelFeeSchema = z.object({
  channel_name: z.string().min(1, 'Channel name is required.'),
  percentage_fee: z.coerce.number().min(0, 'Percentage fee cannot be negative.'),
  fixed_fee: z.coerce.number().min(0, 'Fixed fee cannot be negative.'),
});

export async function upsertChannelFee(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);

        const parsed = UpsertChannelFeeSchema.safeParse({
            channel_name: formData.get('channel_name'),
            percentage_fee: formData.get('percentage_fee'),
            fixed_fee: formData.get('fixed_fee'),
        });
        
        if (!parsed.success) {
            return { success: false, error: parsed.error.issues[0].message };
        }
        
        await db.upsertChannelFeeInDB(companyId, parsed.data);
        revalidatePath('/settings');
        return { success: true };
    } catch(e) {
        logError(e, { context: 'upsertChannelFee action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

// Location Data Actions
export async function getLocations(): Promise<Location[]> {
    const { companyId } = await getAuthContext();
    return db.getLocationsFromDB(companyId);
}

export async function getLocationById(id: string): Promise<Location | null> {
    const { companyId } = await getAuthContext();
    return db.getLocationByIdFromDB(id, companyId);
}

export async function createLocation(data: LocationFormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.createLocationInDB(companyId, data);
        revalidatePath('/locations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'createLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateLocation(id: string, data: LocationFormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.updateLocationInDB(id, companyId, data);
        revalidatePath('/locations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'updateLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteLocation(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const id = formData.get('id') as string;
        if (!id) throw new Error('Location ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.deleteLocationFromDB(id, companyId);
        revalidatePath('/locations');
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

// Supplier Data Actions
export async function getSupplierById(id: string): Promise<Supplier | null> {
    const { companyId } = await getAuthContext();
    return db.getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'createSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData): Promise<{ success: boolean; error?: string }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'updateSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const id = formData.get('id') as string;
        if (!id) throw new Error('Supplier ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.deleteSupplierFromDb(id, companyId);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteInventoryItems(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const skusStr = formData.get('skus') as string;
        if (!skusStr) throw new Error('SKUs are missing.');
        const skus = JSON.parse(skusStr);
        if (!Array.isArray(skus) || skus.length === 0) throw new Error('Invalid SKUs format.');

        const { companyId, userRole, userId } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.softDeleteInventoryItemsFromDb(companyId, skus, userId);
        revalidatePath('/inventory');
        await db.refreshMaterializedViews(companyId);
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteInventoryItems action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateInventoryItem(sku: string, data: InventoryUpdateData): Promise<{ success: boolean; error?: string; updatedItem?: UnifiedInventoryItem }> {
    try {
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const parsedData = InventoryUpdateSchema.safeParse(data);
        if (!parsedData.success) {
            return { success: false, error: "Invalid form data provided." };
        }
        
        const updatedItem = await db.updateInventoryItemInDb(companyId, sku, parsedData.data);
        
        await db.refreshMaterializedViews(companyId);
        revalidatePath('/inventory');
        
        return { success: true, updatedItem };
    } catch (e) {
        logError(e, { context: 'updateInventoryItem action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

// Integrations
export async function getIntegrations(): Promise<Integration[]> {
    const { companyId } = await getAuthContext();
    return db.getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const integrationId = formData.get('integrationId') as string;
        if (!integrationId) throw new Error('Integration ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const integration = await db.getIntegrationsByCompanyId(companyId).then(integrations => integrations.find(i => i.id === integrationId));
        if (!integration) {
            return { success: false, error: "Integration not found or you do not have permission to access it." };
        }
        await db.deleteIntegrationFromDb(integrationId, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'disconnectIntegration' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getInventoryLedger(sku: string): Promise<InventoryLedgerEntry[]> {
    const { companyId } = await getAuthContext();
    return db.getInventoryLedgerForSkuFromDB(companyId, sku);
}

export async function deleteCustomer(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;
        validateCSRF(formData, csrfTokenFromCookie);
        const id = formData.get('id') as string;
        if (!id) throw new Error('Customer ID is missing.');

        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await db.deleteCustomerFromDb(id, companyId);
        revalidatePath('/customers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteCustomer action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function requestCompanyDataExport(): Promise<{ success: boolean; error?: string; jobId?: string }> {
    try {
        const { companyId, userRole, userId } = await getAuthContext();
        requireRole(userRole, ['Owner']); // Only owners can export data

        // Rate limit this expensive operation
        const { limited } = await rateLimit(`export:${companyId}`, 'data_export', 5, 86400); // 5 exports per day
        if (limited) {
            return { success: false, error: 'You have reached the daily export limit. Please try again tomorrow.' };
        }

        const newJob = await db.createExportJobInDb(companyId, userId);
        
        // In a real application, this would trigger a background worker.
        // For this simulation, we just log that the job was created.
        logger.info(`[Data Export] Job ${newJob.id} created for company ${companyId}. Background processing would start here.`);

        revalidatePath('/settings/export');
        return { success: true, jobId: newJob.id };
    } catch(e) {
        logError(e, { context: 'requestCompanyDataExport action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getCustomerAnalytics(): Promise<CustomerAnalytics> {
    const { companyId } = await getAuthContext();
    return db.getCustomerAnalyticsFromDB(companyId);
}

const CUSTOMERS_PER_PAGE = 25;
export async function getCustomersData(params: { query?: string, page?: number }): Promise<{ items: Customer[], totalCount: number }> {
    const { companyId } = await getAuthContext();
    const limit = CUSTOMERS_PER_PAGE;
    const page = params.page || 1;
    const offset = (page - 1) * limit;
    
    return db.getCustomersFromDB(companyId, { query: params.query, limit, offset });
}
