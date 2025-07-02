
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { 
    getDashboardMetrics, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB,
    getDbSchemaAndData,
    getSettings,
    updateSettingsInDb,
    getAnomalyInsightsFromDB,
    getUnifiedInventoryFromDB,
    getInventoryCategoriesFromDB,
    getTeamMembersFromDB,
    inviteUserToCompanyInDb,
    removeTeamMemberFromDb,
    updateTeamMemberRoleInDb,
    getPurchaseOrdersFromDB,
    createPurchaseOrderInDb,
    updatePurchaseOrderInDb,
    deletePurchaseOrderFromDb,
    getPurchaseOrderByIdFromDB,
    receivePurchaseOrderItemsInDB,
    getReorderSuggestionsFromDB,
    getChannelFeesFromDB,
    upsertChannelFeeInDB,
    getLocationsFromDB,
    createLocationInDB,
    updateLocationInDB,
    deleteLocationFromDB,
    getLocationByIdFromDB,
    getSupplierByIdFromDB,
    createSupplierInDb,
    updateSupplierInDb,
    deleteSupplierFromDb,
    deleteInventoryItemsFromDb,
    updateInventoryItemInDb,
    refreshMaterializedViews,
    getIntegrationsByCompanyId,
    deleteIntegrationFromDb,
    getInventoryLedgerForSkuFromDB,
} from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { User, CompanySettings, UnifiedInventoryItem, TeamMember, Anomaly, PurchaseOrder, PurchaseOrderCreateInput, ReorderSuggestion, ReceiveItemsFormInput, PurchaseOrderUpdateInput, ChannelFee, Location, LocationFormData, SupplierFormData, Supplier, InventoryUpdateData, SupplierPerformanceReport, InventoryLedgerEntry, Alert, DeadStockItem } from '@/types';
import { ai } from '@/ai/genkit';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { z } from 'zod';
import { invalidateCompanyCache, isRedisEnabled, redisClient } from '@/lib/redis';
import { revalidatePath } from 'next/cache';
import { validateCSRFToken, CSRF_COOKIE_NAME, CSRF_HEADER_NAME } from '@/lib/csrf';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { PurchaseOrderCreateSchema, PurchaseOrderUpdateSchema, InventoryUpdateSchema } from '@/types';
import { sendPurchaseOrderEmail, sendEmailAlert } from '@/services/email';
import { redirect } from 'next/navigation';
import type { Integration } from '@/features/integrations/types';
import { generateInsightsSummary } from '@/ai/flows/insights-summary-flow';
import { deleteSecret } from '@/features/integrations/services/encryption';

type UserRole = 'Owner' | 'Admin' | 'Member';

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

        const companyId = user?.app_metadata?.company_id;
        const userRole = user?.app_metadata?.role;
        
        if (!user || !companyId || typeof companyId !== 'string' || !userRole) {
            logger.warn('[getAuthContext] Could not determine Company ID or Role. User may not be fully signed up or session is invalid.');
            throw new Error('Your user session is invalid or not fully configured. Please try signing out and signing back in.');
        }
        
        logger.debug(`[getAuthContext] Success. Company ID: ${companyId}, Role: ${userRole}`);
        return { userId: user.id, companyId, userRole: userRole as UserRole };
    } catch (e) {
        logError(e, { context: 'getAuthContext' });
        throw e;
    }
}

function requireRole(currentUserRole: UserRole, allowedRoles: UserRole[]) {
    if (!allowedRoles.includes(currentUserRole)) {
        logger.warn(`[RBAC] Access denied for role '${currentUserRole}'. Allowed roles: ${allowedRoles.join(', ')}.`);
        throw new Error('You do not have permission to perform this action.');
    }
}

function validateCsrf() {
    const tokenFromHeader = headers().get(CSRF_HEADER_NAME);
    const tokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;

    if (!validateCSRFToken(tokenFromHeader, tokenFromCookie)) {
        logger.warn(`[CSRF] Invalid token. Action rejected.`);
        throw new Error('Invalid form submission. Please refresh the page and try again.');
    }
}


export async function getDashboardData(dateRange: string = '30d') {
    try {
        const { companyId } = await getAuthContext();
        return getDashboardMetrics(companyId, dateRange);
    } catch (error) {
        logError(error, { context: 'getDashboardData' });
        throw error;
    }
}

export async function getUnifiedInventory(params: { query?: string; category?: string, location?: string, supplier?: string }): Promise<UnifiedInventoryItem[]> {
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

export async function getPurchaseOrders(): Promise<PurchaseOrder[]> {
    const { companyId } = await getAuthContext();
    return getPurchaseOrdersFromDB(companyId);
}

export async function getPurchaseOrderById(id: string): Promise<PurchaseOrder | null> {
    const { companyId } = await getAuthContext();
    return getPurchaseOrderByIdFromDB(id, companyId);
}

export async function getAlertsData() {
    const { companyId } = await getAuthContext();
    const alerts = await getAlertsFromDB(companyId);
    const lowStockAlerts = alerts.filter(alert => alert.type === 'low_stock');
    if (lowStockAlerts.length > 0) {
        logger.info(`[Alerts] Found ${lowStockAlerts.length} low stock alerts. Simulating email notifications.`);
        for (const alert of lowStockAlerts) {
            sendEmailAlert(alert).catch(err => {
                logError(err, { context: 'Failed to send simulated email alert' });
            });
        }
    }
    return alerts;
}

export async function getDatabaseSchemaAndData() {
    const { companyId } = await getAuthContext();
    return getDbSchemaAndData(companyId);
}

export async function getCompanySettings(): Promise<CompanySettings> {
    const { companyId } = await getAuthContext();
    return getSettings(companyId);
}

export async function getInsightsPageData(): Promise<{ summary: string; anomalies: Anomaly[]; topDeadStock: DeadStockItem[]; topLowStock: Alert[]; }> {
  try {
    const { companyId } = await getAuthContext();
    const [anomalies, deadStockData, alerts] = await Promise.all([
      getAnomalyInsightsFromDB(companyId),
      getDeadStockPageData(companyId),
      getAlertsData(),
    ]);
    const topDeadStock = deadStockData.deadStockItems.sort((a, b) => (b.total_value || 0) - (a.total_value || 0)).slice(0, 5);
    const topLowStock = alerts.filter(a => a.type === 'low_stock').slice(0, 5);
    const summary = await generateInsightsSummary({
      anomalies,
      lowStockCount: alerts.filter(a => a.type === 'low_stock').length,
      deadStockCount: deadStockData.deadStockItems.length,
    });
    return { summary, anomalies, topDeadStock, topLowStock };
  } catch (error) {
    logError(error, { context: 'getInsightsPageData' });
    throw error;
  }
}

export async function updateCompanySettings(settings: Partial<CompanySettings>): Promise<CompanySettings> {
    const { companyId, userRole } = await getAuthContext();
    requireRole(userRole, ['Owner', 'Admin']);
    validateCsrf();
    return updateSettingsInDb(companyId, settings);
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
        validateCsrf();
        const { userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);

        const parsed = InviteTeamMemberSchema.safeParse({ email: formData.get('email') });
        if (!parsed.success) {
            return { success: false, error: parsed.error.issues[0].message };
        }
        const { email } = parsed.data;

        const supabase = getServiceRoleClient();
        const { data: companyData, error: companyError } = await supabase.from('companies').select('name').eq('id', companyId).single();
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
        return { success: false, error: { message: 'Supabase environment variables (NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY) are not set.' }, user: null, isConfigured };
    }
    
    try {
        const cookieStore = cookies();
        const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, { cookies: { get(name: string) { return cookieStore.get(name)?.value; }, }, });
        const { data: { user }, error } = await supabase.auth.getUser();

        if (error) {
            if (error.name === 'AuthError') { return { success: true, error: null, user: null, isConfigured }; }
            return { success: false, error: { message: error.message, details: error }, user: null, isConfigured };
        }
        return { success: true, error: null, user, isConfigured };
    } catch (e) {
        return { success: false, error: { message: getErrorMessage(e), details: e }, user: null, isConfigured };
    }
}

export async function testDatabaseQuery(): Promise<{ success: boolean; count: number | null; error: string | null; }> {
  try {
    const { companyId } = await getAuthContext();
    const serviceSupabase = getServiceRoleClient();
    const { error, count } = await serviceSupabase.from('company_settings').select('*', { count: 'exact', head: true }).eq('company_id', companyId);
    if (error) throw error;
    return { success: true, count: count, error: null };
  } catch (e) {
    let errorMessage = getErrorMessage(e);
    if (errorMessage?.includes('database')) { errorMessage = `Database query failed: ${errorMessage}`; }
    else if (errorMessage?.includes('relation "public.company_settings" does not exist')) { errorMessage = "Database query failed: The 'company_settings' table could not be found. Please ensure your database schema is set up correctly by running the SQL in the setup page."; }
    return { success: false, count: null, error: errorMessage };
  }
}

export async function testMaterializedView(): Promise<{ success: boolean; error: string | null; }> {
    try {
        const serviceSupabase = getServiceRoleClient();
        const { data, error } = await serviceSupabase.from('pg_matviews').select('matviewname').eq('matviewname', 'company_dashboard_metrics').single();
        if (error) {
            if (error.code === 'PGRST116') { return { success: false, error: 'The `company_dashboard_metrics` materialized view is missing. Run the setup SQL for better performance.' }; }
            throw error;
        }
        return { success: !!data, error: null };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function testGenkitConnection(): Promise<{ success: boolean; error: string | null; isConfigured: boolean; }> {
    const isConfigured = !!process.env.GOOGLE_API_KEY;
    if (!isConfigured) { return { success: false, error: 'Genkit is not configured. GOOGLE_API_KEY environment variable is not set.', isConfigured }; }

    try {
        const model = config.ai.model;
        await ai.generate({ model, prompt: 'Test prompt: say "hello".', config: { temperature: 0.1 } });
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

export async function testRedisConnection(): Promise<{ success: boolean; error: string | null; isEnabled: boolean; }> {
    if (!isRedisEnabled) { return { success: true, error: 'Redis is not configured (REDIS_URL is not set), so caching and rate limiting are disabled. This is not a failure.', isEnabled: false }; }
    try {
        const pong = await redisClient.ping();
        if (pong !== 'PONG') { throw new Error('Redis PING command did not return PONG.'); }
        return { success: true, error: null, isEnabled: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e), isEnabled: true };
    }
}

export async function removeTeamMember(memberIdToRemove: string): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { userId: currentUserId, userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        if (memberIdToRemove === currentUserId) { return { success: false, error: "You cannot remove yourself from the team." }; }

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
        validateCsrf();
        const { userRole, companyId } = await getAuthContext();
        requireRole(userRole, ['Owner']);
        const result = await updateTeamMemberRoleInDb(memberIdToUpdate, companyId, newRole);

        if (result.success) {
             logger.info(`[Role Update] User role updated for ${memberIdToUpdate} to ${newRole}`);
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

export async function createPurchaseOrder(data: PurchaseOrderCreateInput): Promise<{ success: boolean, error?: string, data?: PurchaseOrder }> {
  validateCsrf();
  const { companyId, userRole } = await getAuthContext();
  requireRole(userRole, ['Owner', 'Admin']);
  const parsedData = PurchaseOrderCreateSchema.safeParse(data);
  if (!parsedData.success) { return { success: false, error: "Invalid form data provided." }; }
  
  try {
    const newPo = await createPurchaseOrderInDb(companyId, parsedData.data);
    revalidatePath('/purchase-orders', 'layout');
    return { success: true, data: newPo };
  } catch (e) {
    logError(e, { context: 'createPurchaseOrder action' });
    const message = getErrorMessage(e);
    if (message.includes('unique_po_number_per_company')) { return { success: false, error: 'This Purchase Order number already exists. Please use a unique PO number.' }; }
    return { success: false, error: message };
  }
}

export async function updatePurchaseOrder(poId: string, data: PurchaseOrderUpdateInput): Promise<{ success: boolean, error?: string, data?: PurchaseOrder }> {
  validateCsrf();
  const { companyId, userRole } = await getAuthContext();
  requireRole(userRole, ['Owner', 'Admin']);
  const parsedData = PurchaseOrderUpdateSchema.safeParse(data);
  if (!parsedData.success) { return { success: false, error: "Invalid form data provided for update." }; }

  try {
    await updatePurchaseOrderInDb(poId, companyId, parsedData.data);
    revalidatePath('/purchase-orders', 'layout');
    revalidatePath(`/purchase-orders/${poId}`);
    return { success: true };
  } catch (e) {
    logError(e, { context: 'updatePurchaseOrder action' });
    const message = getErrorMessage(e);
    if (message.includes('unique_po_number_per_company')) { return { success: false, error: 'This Purchase Order number already exists. Please use a unique PO number.' }; }
    return { success: false, error: message };
  }
}

export async function deletePurchaseOrder(poId: string): Promise<{ success: boolean, error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await deletePurchaseOrderFromDb(poId, companyId);
        revalidatePath('/purchase-orders', 'layout');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deletePurchaseOrder action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function emailPurchaseOrder(poId: string): Promise<{ success: boolean, error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const purchaseOrder = await getPurchaseOrderByIdFromDB(poId, companyId);
        if (!purchaseOrder) { return { success: false, error: "Purchase Order not found." }; }
        if (!purchaseOrder.supplier_email) { return { success: false, error: "Supplier does not have an email address on file." }; }

        await sendPurchaseOrderEmail(purchaseOrder);
        return { success: true };
    } catch (e) {
        logError(e, { context: `emailPurchaseOrder for PO ${poId}`});
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function receivePurchaseOrderItems(data: ReceiveItemsFormInput): Promise<{ success: boolean, error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await receivePurchaseOrderItemsInDB(data.poId, companyId, data.items);
        await refreshMaterializedViews(companyId);
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
    return getReorderSuggestionsFromDB(companyId);
}

export async function createPurchaseOrdersFromSuggestions(suggestions: ReorderSuggestion[]): Promise<{ success: boolean; error?: string; createdPoCount: number }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);

        if (suggestions.length === 0) { return { success: false, error: "No suggestions were selected.", createdPoCount: 0 }; }

        const groupedBySupplier = suggestions.reduce((acc, suggestion) => {
            const supplierId = suggestion.supplier_id;
            if (!supplierId) return acc;
            if (!acc[supplierId]) { acc[supplierId] = []; }
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
                items: supplierSuggestions.map(s => ({ sku: s.sku, quantity_ordered: s.suggested_reorder_quantity, unit_cost: s.unit_cost, })),
            };
            await createPurchaseOrderInDb(companyId, poInput);
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
    return getChannelFeesFromDB(companyId);
}

const UpsertChannelFeeSchema = z.object({
  channel_name: z.string().min(1, 'Channel name is required.'),
  percentage_fee: z.coerce.number().min(0, 'Percentage fee cannot be negative.'),
  fixed_fee: z.coerce.number().min(0, 'Fixed fee cannot be negative.'),
});

export async function upsertChannelFee(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const parsed = UpsertChannelFeeSchema.safeParse({ channel_name: formData.get('channel_name'), percentage_fee: formData.get('percentage_fee'), fixed_fee: formData.get('fixed_fee'), });
        if (!parsed.success) { return { success: false, error: parsed.error.issues[0].message }; }
        await upsertChannelFeeInDB(companyId, parsed.data);
        revalidatePath('/settings');
        return { success: true };
    } catch(e) {
        logError(e, { context: 'upsertChannelFee action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getLocations(): Promise<Location[]> {
    const { companyId } = await getAuthContext();
    return getLocationsFromDB(companyId);
}

export async function getLocationById(id: string): Promise<Location | null> {
    const { companyId } = await getAuthContext();
    return getLocationByIdFromDB(id, companyId);
}

export async function createLocation(data: LocationFormData): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await createLocationInDB(companyId, data);
        revalidatePath('/locations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'createLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateLocation(id: string, data: LocationFormData): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await updateLocationInDB(id, companyId, data);
        revalidatePath('/locations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'updateLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteLocation(id: string): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await deleteLocationFromDB(id, companyId);
        revalidatePath('/locations');
        revalidatePath('/inventory');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteLocation action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getSupplierById(id: string): Promise<Supplier | null> {
    const { companyId } = await getAuthContext();
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'createSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'updateSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(id: string): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await deleteSupplierFromDb(id, companyId);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteSupplier action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteInventoryItems(skus: string[]): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        await deleteInventoryItemsFromDb(companyId, skus);
        revalidatePath('/inventory');
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(companyId);
        return { success: true };
    } catch (e) {
        logError(e, { context: 'deleteInventoryItems action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateInventoryItem(sku: string, data: InventoryUpdateData): Promise<{ success: boolean; error?: string; updatedItem?: UnifiedInventoryItem }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const parsedData = InventoryUpdateSchema.safeParse(data);
        if (!parsedData.success) { return { success: false, error: "Invalid form data provided." }; }
        
        const updatedItem = await updateInventoryItemInDb(companyId, sku, parsedData.data);
        await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock']);
        await refreshMaterializedViews(companyId);
        revalidatePath('/inventory');
        return { success: true, updatedItem };
    } catch (e) {
        logError(e, { context: 'updateInventoryItem action' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getIntegrations(): Promise<Integration[]> {
    const { companyId } = await getAuthContext();
    return getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(integrationId: string): Promise<{ success: boolean; error?: string }> {
    try {
        validateCsrf();
        const { companyId, userRole } = await getAuthContext();
        requireRole(userRole, ['Owner', 'Admin']);
        const integration = await getIntegrationsByCompanyId(companyId).then(integrations => integrations.find(i => i.id === integrationId));
        if (!integration) { return { success: false, error: "Integration not found or you do not have permission to access it." }; }
        await deleteSecret(companyId, integration.platform);
        await deleteIntegrationFromDb(integrationId, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        logError(e, { context: 'disconnectIntegration' });
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getInventoryLedger(sku: string): Promise<InventoryLedgerEntry[]> {
    const { companyId } = await getAuthContext();
    return getInventoryLedgerForSkuFromDB(companyId, sku);
}
