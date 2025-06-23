
'use server';

import { auth as adminAuth } from '@/lib/firebase-server';
import { supabaseAdmin } from '@/lib/supabase';
import { 
    getDashboardMetrics, 
    getInventoryFromDB, 
    getDeadStockPageData,
    getVendorsFromDB,
    getAlertsFromDB
} from '@/services/database';
import { z } from 'zod';

const IdTokenSchema = z.string();

/**
 * A helper function to verify the user's Firebase token and retrieve their Supabase company ID.
 * Throws an error if authentication fails or the company ID is not found.
 */
async function authenticateAndGetCompanyId(idToken: string): Promise<string> {
    try {
        const decodedToken = await adminAuth.verifyIdToken(idToken);
        const firebaseUid = decodedToken.uid;
      
        const { data, error } = await supabaseAdmin!
            .from('user_profiles')
            .select('company_id')
            .eq('id', firebaseUid)
            .single();
        
        if (error) {
            console.error('Supabase user lookup error:', error);
            throw new Error(`Could not find a profile for user ${firebaseUid}.`);
        }

        if (!data || !data.company_id) {
            throw new Error("User's company profile not found in Supabase.");
        }
      
        return data.company_id;
    } catch (error: any) {
        console.error("Authentication or database error:", error.message);
        throw new Error("Authentication failed or user profile not found.");
    }
}

export async function getDashboardData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getDashboardMetrics(companyId);
}

export async function getInventoryData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getInventoryFromDB(companyId);
}

export async function getDeadStockData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getVendorsFromDB(companyId);
}

export async function getAlertsData(idToken: string) {
    const token = IdTokenSchema.parse(idToken);
    const companyId = await authenticateAndGetCompanyId(token);
    return getAlertsFromDB(companyId);
}
