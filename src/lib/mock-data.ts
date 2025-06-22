import type { Product, Transaction, Supplier, Warehouse, Alert, InventoryValueByCategory, InventoryTrend, InventoryItem } from '@/types';
import { subDays, format, parseISO, isBefore } from 'date-fns';

const today = new Date();

export const mockWarehouses: Warehouse[] = [
    { id: 1, name: 'Main Warehouse', location: 'New York, NY' },
    { id: 2, name: 'West Coast Distribution', location: 'Los Angeles, CA' },
];

export const mockSuppliers: Supplier[] = [
  { id: 1, name: 'Johnson Supply', onTimeDeliveryRate: 98, avgDeliveryTime: 3, contact: 'liam@johnsonsupply.com' },
  { id: 2, name: 'Acme Corp', onTimeDeliveryRate: 92, avgDeliveryTime: 5, contact: 'sarah@acmecorp.com' },
  { id: 3, name: 'Global Parts', onTimeDeliveryRate: 85, avgDeliveryTime: 7, contact: 'mike@globalparts.com' },
];

export const mockProducts: Product[] = [
    { id: 1, sku: 'SKU001', name: 'XYZ Cleaner', quantity: 150, cost: 15, last_sold_date: format(subDays(today, 5), 'yyyy-MM-dd'), warehouse_id: 1, supplier_id: 1, category: 'Cleaning' },
    { id: 2, sku: 'SKU002', name: 'Heavy-Duty Gloves', quantity: 300, cost: 5, last_sold_date: format(subDays(today, 2), 'yyyy-MM-dd'), warehouse_id: 1, supplier_id: 2, category: 'Safety' },
    { id: 3, sku: 'SKU003', name: 'Safety Goggles', quantity: 200, cost: 4, last_sold_date: format(subDays(today, 10), 'yyyy-MM-dd'), warehouse_id: 2, supplier_id: 2, category: 'Safety' },
    { id: 4, sku: 'SKU004', name: 'Industrial Degreaser', quantity: 80, cost: 25, last_sold_date: format(subDays(today, 15), 'yyyy-MM-dd'), warehouse_id: 1, supplier_id: 1, category: 'Cleaning' },
    { id: 5, sku: 'SKU005', name: 'Microfiber Cloths', quantity: 500, cost: 2, last_sold_date: format(subDays(today, 1), 'yyyy-MM-dd'), warehouse_id: 2, supplier_id: 3, category: 'General' },
    { id: 6, sku: 'SKU098', name: 'Obsolete Part X', quantity: 25, cost: 100, last_sold_date: format(subDays(today, 120), 'yyyy-MM-dd'), warehouse_id: 1, supplier_id: 3, category: 'Parts' },
    { id: 7, sku: 'SKU099', name: 'Old Model Cleaner', quantity: 40, cost: 12, last_sold_date: format(subDays(today, 150), 'yyyy-MM-dd'), warehouse_id: 2, supplier_id: 1, category: 'Cleaning' },
];

export const mockTransactions: Transaction[] = Array.from({ length: 180 }).map((_, i) => {
    const product = mockProducts[i % mockProducts.length];
    const date = format(subDays(today, i), 'yyyy-MM-dd');
    const quantity = Math.floor(Math.random() * 5) + 1;
    return {
        id: i + 1,
        product_id: product.id,
        type: 'sale',
        quantity: quantity,
        date: date,
        amount: quantity * product.cost * (1 + Math.random()),
    };
});

export const mockAlerts: Alert[] = [
  { id: 'ALE001', type: 'Low Stock', item: 'XYZ Cleaner', message: 'Quantity is below threshold (150/200)', date: '2023-10-26', resolved: false },
  { id: 'ALE002', type: 'Reorder', item: 'Heavy-Duty Gloves', message: 'Predicted stockout in 7 days.', date: '2023-10-25', resolved: false },
  { id: 'ALE003', name: 'Obsolete Part X', item: 'Obsolete Part X', message: 'Item has not sold in over 90 days.', date: '2023-10-24', resolved: true },
];

export const mockInventoryValueByCategory: InventoryValueByCategory[] = Object.entries(
  mockProducts.reduce(
    (acc, p) => {
      if (!acc[p.category]) acc[p.category] = 0;
      acc[p.category] += p.quantity * p.cost;
      return acc;
    },
    {} as Record<string, number>
  )
).map(([category, value]) => ({ category, value }));

export const mockInventoryTrend: InventoryTrend[] = Array.from({ length: 6 }).map((_, i) => ({
    date: format(subDays(today, (5 - i) * 30), 'MMM'),
    value: parseFloat((1.2 + Math.random() * 0.3 - 0.15).toFixed(2)),
}));

const deadStockProducts = mockProducts.filter(p => isBefore(parseISO(p.last_sold_date), subDays(new Date(), 90)));

export const mockDeadStock = deadStockProducts.map(p => ({
    id: p.sku,
    name: p.name,
    quantity: p.quantity,
    value: p.quantity * p.cost,
    lastSold: p.last_sold_date,
}));

export const mockInventory: InventoryItem[] = mockProducts.map(p => ({
    id: p.sku,
    name: p.name,
    quantity: p.quantity,
    value: p.quantity * p.cost,
    lastSold: p.last_sold_date,
}));
