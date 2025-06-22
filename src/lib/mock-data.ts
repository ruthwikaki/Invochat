import type { Transaction, Warehouse, InventoryValueByCategory, InventoryTrend } from '@/types';
import { subDays, format } from 'date-fns';

const today = new Date();

// Most mock data has been deprecated in favor of live database queries.
// Some chart data remains for purely decorative components.

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

    return {
        mockWarehouses,
        mockTransactions,
        mockInventoryValueByCategory,
        mockInventoryTrend,
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
} = allMockData['default-company-id'];
