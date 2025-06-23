
import type { Transaction, Warehouse, InventoryValueByCategory, InventoryTrend, Product, InventoryItem, Supplier, Alert, DashboardMetrics } from '@/types';
import { subDays, format } from 'date-fns';

const today = new Date();

// This file generates mock data for the application when a database is not connected.

const generateMockData = () => {
    const mockWarehouses: Warehouse[] = [
        { id: 1, name: 'Main Warehouse', location: 'New York, NY' },
        { id: 2, name: 'West Coast Distribution', location: 'Los Angeles, CA' },
    ];

    const mockTransactions: Transaction[] = Array.from({ length: 10 }).map((_, i) => {
        const date = format(subDays(today, i), 'yyyy-MM-dd');
        const quantity = Math.floor(Math.random() * 5) + 1;
        return {
            id: i + 1,
            product_id: i + 1,
            type: 'sale' as 'sale' | 'purchase',
            quantity: quantity,
            date: date,
            amount: quantity * (Math.random() * 50),
        };
    });
    
    const mockInventoryValueByCategory: InventoryValueByCategory[] = [
        { category: 'Cleaning', value: 450000 },
        { category: 'Safety', value: 320000 },
        { category: 'General', value: 180000 },
        { category: 'Parts', value: 250000 },
    ]
    
    const mockInventoryTrend: InventoryTrend[] = Array.from({ length: 6 }).map((_, i) => ({
        date: format(subDays(today, (5 - i) * 30), 'MMM'),
        value: parseFloat((1.2 + Math.random() * 0.3 - 0.15).toFixed(2)),
    }));

    const mockInventoryItems: InventoryItem[] = [
        { id: 'SKU-001', name: 'Industrial Cleaner', quantity: 150, value: 3750, lastSold: format(subDays(today, 5), 'yyyy-MM-dd') },
        { id: 'SKU-002', name: 'Safety Goggles', quantity: 300, value: 1500, lastSold: format(subDays(today, 2), 'yyyy-MM-dd') },
        { id: 'SKU-003', name: 'Heavy Duty Gloves', quantity: 80, value: 1200, lastSold: format(subDays(today, 10), 'yyyy-MM-dd') },
        { id: 'SKU-004', name: 'Absorbent Pads (Pack)', quantity: 200, value: 5000, lastSold: format(subDays(today, 1), 'yyyy-MM-dd') },
        { id: 'SKU-005', name: 'Disinfectant Wipes', quantity: 500, value: 2500, lastSold: format(subDays(today, 3), 'yyyy-MM-dd') },
        { id: 'SKU-006', name: 'Obsolete Widget A', quantity: 50, value: 250, lastSold: format(subDays(today, 100), 'yyyy-MM-dd') },
        { id: 'SKU-007', name: 'Forgotten Gadget B', quantity: 25, value: 750, lastSold: format(subDays(today, 120), 'yyyy-MM-dd') },
    ];

     const mockProducts: Product[] = mockInventoryItems.map(item => ({
        id: parseInt(item.id.replace('SKU-', '')),
        sku: item.id,
        name: item.name,
        quantity: item.quantity,
        cost: item.value / item.quantity,
        last_sold_date: item.lastSold,
        warehouse_id: 1,
        supplier_id: 1,
        category: 'General'
    }));

    const mockSuppliers: Supplier[] = [
        { id: 1, name: 'Global Supplies Co.', onTimeDeliveryRate: 98.5, avgDeliveryTime: 5, contact: 'sales@globalsupplies.com' },
        { id: 2, name: 'Industrial Safety Inc.', onTimeDeliveryRate: 95.2, avgDeliveryTime: 7, contact: 'orders@industrialsafety.com' },
        { id: 3, name: 'Regional Cleaners', onTimeDeliveryRate: 99.1, avgDeliveryTime: 3, contact: 'contact@regionalcleaners.net' },
        { id: 4, name: 'Parts R Us', onTimeDeliveryRate: 88.0, avgDeliveryTime: 10, contact: 'support@partsrus.co' },
    ];
    
    const mockAlerts: Alert[] = [
        { id: 'L-001', type: 'Low Stock', item: 'Heavy Duty Gloves', message: 'Quantity is critically low at 80 units.', date: new Date().toISOString(), resolved: false },
        { id: 'D-001', type: 'Dead Stock', item: 'Obsolete Widget A', message: 'Item has not sold in over 90 days.', date: subDays(today, 2).toISOString(), resolved: true },
    ];
    
    const mockDashboardMetrics: DashboardMetrics = {
        inventoryValue: 13950,
        deadStockValue: 1000,
        onTimeDeliveryRate: 95.2,
        predictiveAlert: {
            item: 'Heavy Duty Gloves',
            days: 12
        }
    };

    return {
        mockWarehouses,
        mockTransactions,
        mockInventoryValueByCategory,
        mockInventoryTrend,
        mockInventoryItems,
        mockProducts,
        mockSuppliers,
        mockAlerts,
        mockDashboardMetrics,
    }
}

export const allMockData: Record<string, ReturnType<typeof generateMockData>> = {
    'default-company-id': generateMockData()
}

// Re-export individual mocks for pages that don't need multi-tenancy yet.
export const {
    mockWarehouses,
    mockTransactions,
    mockInventoryValueByCategory,
    mockInventoryTrend,
    mockInventoryItems,
    mockProducts,
    mockSuppliers,
    mockAlerts,
    mockDashboardMetrics,
} = allMockData['default-company-id'];
