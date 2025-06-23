'use server';

import { 
    getCompanyIdForUser, 
    getDashboardMetrics, 
    getInventoryItems, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB
} from '@/services/database';
import { supabase } from '@/lib/db';
import { z } from 'zod';

const IdTokenSchema = z.string(); // Supabase Access Token

/**
 * A helper function to verify the user's token and retrieve their company ID.
 * Throws an error if authentication fails or the company ID is not found.
 */
async function authenticateAndGetCompanyId(idToken: string): Promise<string> {
    const { data: { user }, error } = await supabase.auth.getUser(idToken);
    if (error || !user) {
        throw new Error("Authentication failed. Invalid token.");
    }
    
    const companyId = await getCompanyIdForUser(user.id);
    if (!companyId) {
        throw new Error("User's company profile not found.");
    }
    return companyId;
}

export async function getDashboardData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getDashboardMetrics(companyId);
}

export async function getInventory(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getInventoryItems(companyId);
}

export async function getDeadStockData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getSuppliersFromDB(companyId);
}

export async function getAlertsData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getAlertsFromDB(companyId);
}
