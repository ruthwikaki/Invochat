
'use server';

import { createClient } from '@/lib/supabase/server';
import { cookies } from 'next/headers';
import { 
    getDashboardMetrics, 
    getInventoryItems, 
    getDeadStockPageData,
    getSuppliersFromDB,
    getAlertsFromDB
} from '@/services/database';
import type { User } from '@/types';

const SUPABASE_CONFIGURED = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

async function getCompanyIdForCurrentUser(): Promise<string> {
    if (!SUPABASE_CONFIGURED) {
        throw new Error("Database is not configured. Please set Supabase environment variables.");
    }
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    const { data: { user } } = await supabase.auth.getUser();

    const companyId = user?.app_metadata?.company_id;

    if (!companyId) {
        throw new Error("User is not associated with a company.");
    }
    return companyId;
}

export async function getDashboardData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDashboardMetrics(companyId);
}

export async function getInventoryData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getInventoryItems(companyId);
}

export async function getDeadStockData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getDeadStockPageData(companyId);
}

export async function getSuppliersData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getSuppliersFromDB(companyId);
}

export async function getAlertsData() {
    const companyId = await getCompanyIdForCurrentUser();
    return getAlertsFromDB(companyId);
}


export async function testSupabaseConnection(): Promise<{
    success: boolean;
    error: { message: string; details?: any; } | null;
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
        const supabase = createClient(cookieStore);
        const { data: { user }, error } = await supabase.auth.getUser();

        if (error) {
            if (error.name === 'AuthSessionMissingError') {
                 return {
                    success: true,
                    error: null,
                    user: null,
                    isConfigured
                };
            }
            
            return {
                success: false,
                error: { message: 'An unexpected error occurred while fetching the user.', details: error },
                user: null,
                isConfigured
            };
        }

        return {
            success: true,
            error: null,
            user,
            isConfigured
        };

    } catch (e: any) {
        return {
            success: false,
            error: { message: 'A server-side error occurred while trying to connect to Supabase.', details: e.message },
            user: null,
            isConfigured
        };
    }
}
