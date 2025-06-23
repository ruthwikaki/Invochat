
/**
 * @fileoverview
 * This file provides functions to query the PostgreSQL database. It uses the
 * connection pool from /src/lib/db.ts and ensures all queries are tenant-aware
 * by using the companyId.
 * When the database is not connected, it returns mock data for demonstration.
 */

import { db, isDbConnected } from '@/lib/db';
import { allMockData } from '@/lib/mock-data';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics } from '@/types';
import { format, subDays } from 'date-fns';

// Helper to convert database snake_case to JS camelCase
// e.g., on_time_delivery_rate -> onTimeDeliveryRate
const toCamelCase = (rows: any[]) => {
  if (!rows) return [];
  return rows.map(row => {
    const newRow: { [key: string]: any } = {};
    for (const key in row) {
      const camelKey = key.replace(/_([a-z])/g, g => g[1].toUpperCase());
      newRow[camelKey] = row[key];
    }
    return newRow;
  });
};

/**
 * Retrieves the company ID for a given Firebase user UID.
 * This is a critical function; if it fails, we throw because we can't identify the tenant.
 * @param uid The Firebase user ID.
 * @returns A promise that resolves to the company ID string or null if not found.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    if (!isDbConnected()) return 'default-company-id';
    const sqlQuery = 'SELECT company_id FROM users WHERE firebase_uid = $1;';
    try {
        const { rows } = await db.query(sqlQuery, [uid]);
        return rows[0]?.company_id || null;
    } catch (error) {
        console.error('[DB Service] CRITICAL: Database query failed in getCompanyIdForUser:', error);
        return null;
    }
}

/**
 * Creates a new company and a user associated with it in the database.
 * This function uses a transaction to ensure both operations succeed or fail together.
 * This is a critical function and will throw on failure.
 * @param uid The Firebase user ID.
 * @param email The user's email.
 * @param companyName The name of the new company.
 * @returns A promise that resolves to the new company's ID.
 */
export async function createCompanyAndUserInDB(uid: string, email: string, companyName: string): Promise<string> {
    if (!isDbConnected()) {
        console.log(`[Mock DB] Skipping user/company creation for ${email}.`);
        return 'default-company-id';
    }
    const client = await db.connect();
    try {
        await client.query('BEGIN');
        
        // 1. Create the company
        const companyQuery = 'INSERT INTO companies (name, owner_uid) VALUES ($1, $2) RETURNING id;';
        const companyResult = await client.query(companyQuery, [companyName, uid]);
        const companyId = companyResult.rows[0].id;

        // 2. Create the user and link to the company
        const userQuery = 'INSERT INTO users (firebase_uid, email, company_id) VALUES ($1, $2, $3);';
        await client.query(userQuery, [uid, email, companyId]);

        await client.query('COMMIT');
        return companyId;
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('[DB Service] CRITICAL: Database transaction failed in createCompanyAndUserInDB:', error);
        throw new Error('Failed to create company and user in database.');
    } finally {
        client.release();
    }
}

/**
 * Executes a query to fetch data for chart generation from PostgreSQL.
 * Returns mock data or an empty array on database failure.
 * @param query A natural language description of the data needed.
 * @param companyId The ID of the company whose data is being queried.
 * @returns An array of data matching the query.
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
    const companyMockData = allMockData[companyId];

    if (!isDbConnected()) {
         if (query.toLowerCase().includes('inventory value by category')) {
            return companyMockData.mockInventoryValueByCategory.map(d => ({ name: d.category, value: d.value }));
        }
        return []; // Return empty for other chart queries in mock mode for now.
    }

    const lowerCaseQuery = query.toLowerCase();
    let sqlQuery: string;
    const params: (string|number)[] = [companyId];

    if (lowerCaseQuery.includes('slowest moving') || lowerCaseQuery.includes('dead stock value')) {
        sqlQuery = `
            SELECT name, quantity * cost as value
            FROM inventory 
            WHERE company_id = $1 AND last_sold_date < NOW() - INTERVAL '90 days'
            ORDER BY last_sold_date ASC 
            LIMIT 5;
        `;
    } else if (lowerCaseQuery.includes('warehouse distribution')) {
        sqlQuery = `
            SELECT w.name, SUM(i.quantity * i.cost) as value 
            FROM inventory i 
            JOIN warehouses w ON i.warehouse_id = w.id 
            WHERE i.company_id = $1 
            GROUP BY w.name;
        `;
    } else if (lowerCaseQuery.includes('sales velocity')) {
        sqlQuery = `
            SELECT i.category as name, SUM(s.quantity) as value 
            FROM sales s 
            JOIN inventory i ON s.product_id = i.id 
            WHERE i.company_id = $1 AND s.date > NOW() - INTERVAL '30 days'
            GROUP BY i.category;
        `;
    } else if (lowerCaseQuery.includes('inventory aging')) {
        sqlQuery = `
            SELECT
                CASE
                    WHEN last_sold_date >= NOW() - INTERVAL '30 days' THEN '0-30 Days'
                    WHEN last_sold_date >= NOW() - INTERVAL '60 days' THEN '31-60 Days'
                    WHEN last_sold_date >= NOW() - INTERVAL '90 days' THEN '61-90 Days'
                    ELSE '90+ Days'
                END as name,
                SUM(quantity * cost) as value
            FROM inventory
            WHERE company_id = $1
            GROUP BY name
            ORDER BY 
                CASE name
                    WHEN '0-30 Days' THEN 1
                    WHEN '31-60 Days' THEN 2
                    WHEN '61-90 Days' THEN 3
                    ELSE 4
                END;
        `;
    } else if (lowerCaseQuery.includes('supplier performance')) {
        sqlQuery = `
            SELECT name, on_time_delivery_rate as value 
            FROM suppliers 
            WHERE company_id = $1 
            ORDER BY value DESC;
        `;
    } else { // Default to 'inventory value by category'
        sqlQuery = `
            SELECT category as name, SUM(quantity * cost) as value 
            FROM inventory 
            WHERE company_id = $1 
            GROUP BY category;
        `;
    }

    try {
        const { rows } = await db.query(sqlQuery, params);
        return rows.map(row => ({...row, value: parseFloat(row.value)}));
    } catch (error) {
        console.error('[DB Service] Query failed in getDataForChart. Returning empty array.', error);
        return [];
    }
}

/**
 * Retrieves dead stock items from the database for the AI flow.
 * Returns mock data or an empty array on database failure.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of dead stock products.
 */
export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
    if (!isDbConnected()) {
        const mockProducts = allMockData[companyId]?.mockProducts || [];
        return mockProducts.filter(p => new Date(p.last_sold_date) < subDays(new Date(), 90));
    }
    const sqlQuery = `
        SELECT id, sku, name, quantity, cost, last_sold_date, warehouse_id, supplier_id, category 
        FROM inventory
        WHERE company_id = $1 AND last_sold_date < NOW() - INTERVAL '90 days';
    `;
    try {
        const { rows } = await db.query(sqlQuery, [companyId]);
        return toCamelCase(rows.map(row => ({
            ...row,
            last_sold_date: format(new Date(row.last_sold_date), 'yyyy-MM-dd')
        }))) as Product[];
    } catch (error) {
        console.error('[DB Service] Query failed in getDeadStockFromDB. Returning empty array.', error);
        return [];
    }
}

/**
 * Retrieves suppliers from the database, ranked by performance.
 * Returns mock data or an empty array on database failure.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of suppliers.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockSuppliers || [];
    const sqlQuery = `
        SELECT id, name, on_time_delivery_rate, avg_delivery_time, contact 
        FROM suppliers
        WHERE company_id = $1
        ORDER BY on_time_delivery_rate DESC;
    `;
    try {
        const { rows } = await db.query(sqlQuery, [companyId]);
        return toCamelCase(rows) as Supplier[];
    } catch (error) {
        console.error('[DB Service] Query failed in getSuppliersFromDB. Returning empty array.', error);
        return [];
    }
}

/**
 * Retrieves all inventory items for a company.
 * Returns mock data or an empty array on database failure.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of inventory items.
 */
export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockInventoryItems || [];
    const sqlQuery = `
        SELECT sku as id, name, quantity, (quantity * cost) as value, last_sold_date
        FROM inventory
        WHERE company_id = $1
        ORDER BY name;
    `;
    try {
        const { rows } = await db.query(sqlQuery, [companyId]);
        return rows.map(row => ({
            ...row,
            value: parseFloat(row.value),
            lastSold: format(new Date(row.last_sold_date), 'yyyy-MM-dd')
        }));
    } catch (error) {
        console.error('[DB Service] Query failed in getInventoryItems. Returning empty array.', error);
        return [];
    }
}

/**
 * Retrieves data for the Dead Stock page.
 * Returns mock data or default values on database failure.
 * @param companyId The company's ID.
 */
export async function getDeadStockPageData(companyId: string) {
    if (!isDbConnected()) {
        const mockItems = allMockData[companyId]?.mockInventoryItems || [];
        const deadStockItems = mockItems.filter(item => new Date(item.lastSold) < subDays(new Date(), 90));
        const totalDeadStockValue = deadStockItems.reduce((acc, item) => acc + item.value, 0);
        return { deadStockItems, totalDeadStockValue };
    }

    const sqlQuery = `
        SELECT sku as id, name, quantity, (quantity * cost) as value, last_sold_date as lastSold
        FROM inventory
        WHERE company_id = $1 AND last_sold_date < NOW() - INTERVAL '90 days'
        ORDER BY value DESC;
    `;
    try {
        const { rows } = await db.query(sqlQuery, [companyId]);
        const deadStockItems = rows.map(row => ({
            ...row,
            value: parseFloat(row.value),
            lastSold: format(new Date(row.lastSold), 'yyyy-MM-dd')
        }));
        
        const totalDeadStockValue = deadStockItems.reduce((acc, item) => acc + item.value, 0);

        return { deadStockItems, totalDeadStockValue };
    } catch (error) {
        console.error('[DB Service] Query failed in getDeadStockPageData. Returning default values.', error);
        return { deadStockItems: [], totalDeadStockValue: 0 };
    }
}


/**
 * Retrieves alerts.
 * Returns mock data or an empty array on database failure.
 * @param companyId The company's ID.
 * @returns A promise resolving to an array of alerts.
 */
export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
    if (!isDbConnected()) return allMockData[companyId]?.mockAlerts || [];
    try {
        // Low stock alerts
        const lowStockSql = `
            SELECT name, quantity FROM inventory 
            WHERE company_id = $1 AND quantity < 100 ORDER BY quantity ASC LIMIT 2;
        `;
        const lowStockRes = await db.query(lowStockSql, [companyId]);
        const lowStockAlerts: Alert[] = lowStockRes.rows.map((item, i) => ({
            id: `L-00${i+1}`,
            type: 'Low Stock',
            item: item.name,
            message: `Quantity is critically low at ${item.quantity} units.`,
            date: new Date().toISOString(),
            resolved: false
        }));

        // Dead stock alerts
        const deadStockSql = `
            SELECT name, last_sold_date FROM inventory 
            WHERE company_id = $1 AND last_sold_date < NOW() - INTERVAL '90 days' 
            ORDER BY last_sold_date ASC LIMIT 2;
        `;
        const deadStockRes = await db.query(deadStockSql, [companyId]);
        const deadStockAlerts: Alert[] = deadStockRes.rows.map((item, i) => ({
            id: `D-00${i+1}`,
            type: 'Dead Stock',
            item: item.name,
            message: `Item has not sold in over 90 days (last sold: ${format(new Date(item.last_sold_date), 'MMM d, yyyy')}).`,
            date: new Date().toISOString(),
            resolved: false
        }));

        return [...lowStockAlerts, ...deadStockAlerts];
    } catch (error) {
        console.error('[DB Service] Query failed in getAlertsFromDB. Returning empty array.', error);
        return [];
    }
}

/**
 * Retrieves key metrics for the dashboard.
 * Returns mock data or default values on database failure.
 * @param companyId The company's ID.
 * @returns A promise resolving to an object with dashboard metrics.
 */
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
    const defaultMetrics: DashboardMetrics = {
        inventoryValue: 0,
        deadStockValue: 0,
        onTimeDeliveryRate: 0,
        predictiveAlert: null,
    };
    
    if (!isDbConnected()) return allMockData[companyId]?.mockDashboardMetrics || defaultMetrics;
    
    try {
        const client = await db.connect();
        try {
            const queries = [
                client.query('SELECT SUM(quantity * cost) as value FROM inventory WHERE company_id = $1', [companyId]),
                client.query('SELECT SUM(quantity * cost) as value FROM inventory WHERE company_id = $1 AND last_sold_date < NOW() - INTERVAL \'90 days\'', [companyId]),
                client.query('SELECT AVG(on_time_delivery_rate) as value FROM suppliers WHERE company_id = $1', [companyId]),
                client.query('SELECT name, last_sold_date, quantity FROM inventory WHERE company_id = $1 AND quantity > 0 ORDER BY quantity ASC, last_sold_date ASC LIMIT 1', [companyId])
            ];

            const [
                inventoryValueRes,
                deadStockValueRes,
                onTimeDeliveryRateRes,
                predictiveAlertRes
            ] = await Promise.all(queries);

            const inventoryValue = parseFloat(inventoryValueRes.rows[0]?.value) || 0;
            const deadStockValue = parseFloat(deadStockValueRes.rows[0]?.value) || 0;
            const onTimeDeliveryRate = parseFloat(onTimeDeliveryRateRes.rows[0]?.value) || 0;
            
            let predictiveAlert = null;
            if (predictiveAlertRes.rows[0]) {
                const item = predictiveAlertRes.rows[0];
                // simple prediction: assume we sell 1 unit/day
                const days = Math.round(item.quantity); 
                predictiveAlert = { item: item.name, days };
            }

            return {
                inventoryValue,
                deadStockValue,
                onTimeDeliveryRate,
                predictiveAlert,
            };

        } finally {
            client.release();
        }
    } catch (error) {
        console.error('[DB Service] Query failed in getDashboardMetrics. Returning default values.', error);
        return defaultMetrics;
    }
}
