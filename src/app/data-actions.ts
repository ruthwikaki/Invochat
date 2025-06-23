
'use server';

import { 
    getDashboardMetrics, 
    getInventoryFromDB, 
    getDeadStockPageData,
    getVendorsFromDB,
    getAlertsFromDB
} from '@/services/database';

const DEMO_COMPANY_ID = '550e8400-e29b-41d4-a716-446655440001';

export async function getDashboardData() {
    return getDashboardMetrics(DEMO_COMPANY_ID);
}

export async function getInventoryData() {
    return getInventoryFromDB(DEMO_COMPANY_ID);
}

export async function getDeadStockData() {
    return getDeadStockPageData(DEMO_COMPANY_ID);
}

export async function getSuppliersData() {
    return getVendorsFromDB(DEMO_COMPANY_ID);
}

export async function getAlertsData() {
    return getAlertsFromDB(DEMO_COMPANY_ID);
}
