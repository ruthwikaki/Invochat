/**
 * @fileoverview
 * This file provides functions to query the PostgreSQL database. It uses the
 * connection pool from /src/lib/db.ts and ensures all queries are tenant-aware
 * by using the companyId.
 */

import { db } from '@/lib/db';
import type { Product, Supplier, InventoryItem, Alert, DashboardMetrics } from '@/types';
import { format, formatDistanceToNow } from 'date-fns';

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
 * @param uid The Firebase user ID.
 * @returns A promise that resolves to the company ID string or null if not found.
 */
export async function getCompanyIdForUser(uid: string): Promise<string | null> {
    const sqlQuery = 'SELECT company_id FROM users WHERE firebase_uid = $1;';
    try {
        const { rows } = await db.query(sqlQuery, [uid]);
        return rows[0]?.company_id || null;
    } catch (error) {
        console.error('Database query failed in getCompanyIdForUser:', error);
        throw new Error('Failed to retrieve user company information.');
    }
}

/**
 * Creates a new company and a user associated with it in the database.
 * This function uses a transaction to ensure both operations succeed or fail together.
 * @param uid The Firebase user ID.
 * @param email The user's email.
 * @param companyName The name of the new company.
 * @returns A promise that resolves to the new company's ID.
 */
export async function createCompanyAndUserInDB(uid: string, email: string, companyName: string): Promise<string> {
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
        console.error('Database transaction failed in createCompanyAndUserInDB:', error);
        throw new Error('Failed to create company and user in database.');
    } finally {
        client.release();
    }
}

/**
 * Executes a query to fetch data for chart generation from PostgreSQL.
 * @param query A natural language description of the data needed.
 * @param companyId The ID of the company whose data is being queried.
 * @returns An array of data matching the query.
 */
export async function getDataForChart(query: string, companyId: string): Promise<any[]> {
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
        console.error('Database query failed in getDataForChart:', error);
        throw new Error('Failed to fetch chart data from the database.');
    }
}

/**
 * Retrieves dead stock items from the database for the AI flow.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of dead stock products.
 */
export async function getDeadStockFromDB(companyId: string): Promise<Product[]> {
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
        console.error('Database query failed in getDeadStockFromDB:', error);
        throw new Error('Failed to fetch dead stock data.');
    }
}

/**
 * Retrieves suppliers from the database, ranked by performance.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of suppliers.
 */
export async function getSuppliersFromDB(companyId: string): Promise<Supplier[]> {
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
        console.error('Database query failed in getSuppliersFromDB:', error);
        throw new Error('Failed to fetch supplier data.');
    }
}

/**
 * Retrieves all inventory items for a company.
 * @param companyId The company's ID.
 * @returns A promise that resolves to an array of inventory items.
 */
export async function getInventoryItems(companyId: string): Promise<InventoryItem[]> {
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
        console.error('Database query failed in getInventoryItems:', error);
        throw new Error('Failed to fetch inventory items.');
    }
}

/**
 * Retrieves data for the Dead Stock page.
 * @param companyId The company's ID.
 */
export async function getDeadStockPageData(companyId: string) {
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
        console.error('Database query failed in getDeadStockPageData:', error);
        throw new Error('Failed to fetch dead stock page data.');
    }
}


/**
 * Fabricates alerts based on current inventory data.
 * @param companyId The company's ID.
 * @returns A promise resolving to an array of alerts.
 */
export async function getAlertsFromDB(companyId: string): Promise<Alert[]> {
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
        console.error('Database query failed in getAlertsFromDB:', error);
        throw new Error('Failed to generate alerts from database.');
    }
}

/**
 * Retrieves key metrics for the dashboard.
 * @param companyId The company's ID.
 * @returns A promise resolving to an object with dashboard metrics.
 */
export async function getDashboardMetrics(companyId: string): Promise<DashboardMetrics> {
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
        console.error('Database query failed in getDashboardMetrics:', error);
        throw new Error('Failed to fetch dashboard metrics.');
    }
}
