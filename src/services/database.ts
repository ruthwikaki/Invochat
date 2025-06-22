/**
 * @fileoverview
 * This file simulates a database service. It provides functions to query
 * mock data, mimicking interactions with a real database. In a real application,
 * these functions would execute SQL queries against a database.
 */

import { mockProducts, mockSuppliers, mockTransactions, mockWarehouses } from '@/lib/mock-data';
import type { Product } from '@/types';
import { subDays, parseISO, isBefore } from 'date-fns';

// Helper to calculate inventory value for a product
const getProductValue = (product: Product) => product.quantity * product.cost;

/**
 * Simulates executing a query to fetch data for chart generation.
 * This is a simplified mock of a database query engine.
 * @param query A natural language description of the data needed.
 * @returns An array of data matching the query.
 */
export async function getDataForChart(query: string): Promise<any[]> {
    const lowerCaseQuery = query.toLowerCase();

    if (lowerCaseQuery.includes('slowest moving') || lowerCaseQuery.includes('dead stock')) {
        // Return top 5 slowest moving items by value
        return mockProducts
            .sort((a, b) => new Date(a.last_sold_date).getTime() - new Date(b.last_sold_date).getTime())
            .slice(0, 5)
            .map(p => ({ name: p.name, value: getProductValue(p), last_sold: p.last_sold_date }));
    }

    if (lowerCaseQuery.includes('warehouse distribution')) {
        const distribution = mockProducts.reduce((acc, product) => {
            const warehouse = mockWarehouses.find(w => w.id === product.warehouse_id);
            if (warehouse) {
                if (!acc[warehouse.name]) {
                    acc[warehouse.name] = 0;
                }
                acc[warehouse.name] += getProductValue(product);
            }
            return acc;
        }, {} as Record<string, number>);

        return Object.entries(distribution).map(([name, value]) => ({ name, value }));
    }

    if (lowerCaseQuery.includes('sales velocity')) {
        const salesByCategory = mockTransactions
            .filter(t => t.type === 'sale')
            .reduce((acc, transaction) => {
                const product = mockProducts.find(p => p.id === transaction.product_id);
                if (product) {
                    const category = product.category;
                    if (!acc[category]) {
                        acc[category] = 0;
                    }
                    acc[category] += transaction.quantity;
                }
                return acc;
            }, {} as Record<string, number>);
        
        return Object.entries(salesByCategory).map(([name, value]) => ({ name, value }));
    }

    if (lowerCaseQuery.includes('inventory aging')) {
        const today = new Date();
        const aging = {
            '0-30 Days': 0,
            '31-60 Days': 0,
            '61-90 Days': 0,
            '90+ Days': 0,
        };

        mockProducts.forEach(p => {
            const lastSoldDate = parseISO(p.last_sold_date);
            if (isBefore(lastSoldDate, subDays(today, 90))) {
                aging['90+ Days'] += getProductValue(p);
            } else if (isBefore(lastSoldDate, subDays(today, 60))) {
                aging['61-90 Days'] += getProductValue(p);
            } else if (isBefore(lastSoldDate, subDays(today, 30))) {
                aging['31-60 Days'] += getProductValue(p);
            } else {
                aging['0-30 Days'] += getProductValue(p);
            }
        });

        return Object.entries(aging).map(([name, value]) => ({ name, value }));
    }
    
    if (lowerCaseQuery.includes('supplier performance')) {
        return mockSuppliers.map(s => ({
            name: s.name,
            value: s.onTimeDeliveryRate
        })).sort((a, b) => b.value - a.value);
    }
    
    if (lowerCaseQuery.includes('inventory value by category')) {
         const valueByCategory = mockProducts.reduce((acc, product) => {
            if (!acc[product.category]) {
                acc[product.category] = 0;
            }
            acc[product.category] += getProductValue(product);
            return acc;
        }, {} as Record<string, number>);

        return Object.entries(valueByCategory).map(([name, value]) => ({ name, value }));
    }

    // Default: return inventory value by category if no match
    return getDataForChart('inventory value by category');
}

export async function getDeadStockFromDB() {
    const ninetyDaysAgo = subDays(new Date(), 90);
    return mockProducts.filter(p => isBefore(parseISO(p.last_sold_date), ninetyDaysAgo));
}

export async function getSuppliersFromDB() {
    return mockSuppliers.sort((a,b) => b.onTimeDeliveryRate - a.onTimeDeliveryRate);
}
