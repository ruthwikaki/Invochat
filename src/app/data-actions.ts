
'use server';
import { db } from '@/lib/database-queries';
import { getCurrentCompanyId, getCurrentUser } from '@/lib/auth-helpers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { getDeadStockReportFromDB, getSupplierByIdFromDB, createSupplierInDb, updateSupplierInDb, deleteSupplierFromDb, getIntegrationsByCompanyId, deleteIntegrationFromDb, getTeamMembersFromDB, inviteUserToCompanyInDb, removeTeamMemberFromDb, updateTeamMemberRoleInDb, getCompanyById } from '@/services/database';
import { SupplierFormData } from '@/types';
import { validateCSRF } from '@/lib/csrf';

export async function getProducts() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  return await db.getCompanyProducts(companyId);
}

export async function getOrders() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  return await db.getCompanyOrders(companyId);
}

export async function getCustomers() {
  const companyId = await getCurrentCompanyId();
  if (!companyId) throw new Error('Unauthorized');
  
  return await db.getCompanyCustomers(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return await db.getCompanySuppliers(companyId);
}

export async function getDeadStockPageData() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    const settings = await getCompanySettings();
    const deadStockData = await getDeadStockReportFromDB(companyId);
    return {
        ...deadStockData,
        deadStockDays: settings.dead_stock_days
    };
}

export async function getSupplierById(id: string) {
    const companyId = await getCurrentCompanyId();
    if (!companyId) throw new Error('Unauthorized');
    return getSupplierByIdFromDB(id, companyId);
}

export async function createSupplier(data: SupplierFormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await createSupplierInDb(companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function updateSupplier(id: string, data: SupplierFormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await updateSupplierInDb(id, companyId, data);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function deleteSupplier(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const id = formData.get('id') as string;
        await deleteSupplierFromDb(id, companyId);
        revalidatePath('/suppliers');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getIntegrations() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getIntegrationsByCompanyId(companyId);
}

export async function disconnectIntegration(formData: FormData) {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const id = formData.get('integrationId') as string;
        await deleteIntegrationFromDb(id, companyId);
        revalidatePath('/settings/integrations');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

export async function getTeamMembers() {
    const companyId = await getCurrentCompanyId();
    if (!companyId) return [];
    return getTeamMembersFromDB(companyId);
}

export async function inviteTeamMember(formData: FormData): Promise<{ success: boolean, error?: string }> {
    try {
        const companyId = await getCurrentCompanyId();
        if (!companyId) throw new Error('Unauthorized');
        
        await validateCSRF(formData);
        const email = formData.get('email') as string;
        const company = await getCompanyById(companyId);
        await inviteUserToCompanyInDb(companyId, company?.name || 'your company', email);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function removeTeamMember(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const user = await getCurrentUser();
        const companyId = await getCurrentCompanyId();
        if (!companyId || !user) throw new Error('Unauthorized');

        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        if (user.id === memberId) throw new Error("You cannot remove yourself.");
        
        await removeTeamMemberFromDb(memberId, companyId);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch (e) {
        return { success: false, error: getErrorMessage(e) };
    }
}
export async function updateTeamMemberRole(formData: FormData): Promise<{ success: boolean; error?: string }> {
    try {
        const user = await getCurrentUser();
        const companyId = await getCurrentCompanyId();
        if (!companyId || !user) throw new Error('Unauthorized');
        await validateCSRF(formData);
        const memberId = formData.get('memberId') as string;
        const newRole = formData.get('newRole') as 'Admin' | 'Member';
        if (!['Admin', 'Member'].includes(newRole)) throw new Error('Invalid role specified.');
        if (user.id === memberId) throw new Error("You cannot change your own role.");
        
        await updateTeamMemberRoleInDb(memberId, companyId, newRole);
        revalidatePath('/settings/profile');
        return { success: true };
    } catch(e) {
        return { success: false, error: getErrorMessage(e) };
    }
}

// ... other actions ...
export * from './actions';

    