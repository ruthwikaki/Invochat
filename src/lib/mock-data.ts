import type { InventoryItem, DeadStockItem, Supplier, Alert, InventoryValueByCategory, InventoryTrend } from '@/types';

export const mockInventory: InventoryItem[] = [
  { id: 'SKU001', name: 'XYZ Cleaner', quantity: 150, value: 2250, lastSold: '2023-10-26' },
  { id: 'SKU002', name: 'Heavy-Duty Gloves', quantity: 300, value: 1500, lastSold: '2023-10-25' },
  { id: 'SKU003', name: 'Safety Goggles', quantity: 200, value: 800, lastSold: '2023-10-24' },
  { id: 'SKU004', name: 'Industrial Degreaser', quantity: 80, value: 1200, lastSold: '2023-10-22' },
  { id: 'SKU005', name: 'Microfiber Cloths (100-pack)', quantity: 500, value: 2500, lastSold: '2023-10-26' },
];

export const mockDeadStock: DeadStockItem[] = [
    { id: 'SKU098', name: 'Obsolete Part X', quantity: 25, value: 2500, lastSold: '2022-01-15', reason: 'Not sold in 90+ days' },
    { id: 'SKU099', name: 'Old Model Cleaner', quantity: 40, value: 480, lastSold: '2022-03-02', reason: 'Not sold in 90+ days' },
];

export const mockSuppliers: Supplier[] = [
  { id: 'SUP001', name: 'Johnson Supply', onTimeDeliveryRate: 98, avgDeliveryTime: 3, recentOrders: 12, contact: 'liam@johnsonsupply.com' },
  { id: 'SUP002', name: 'Acme Corp', onTimeDeliveryRate: 92, avgDeliveryTime: 5, recentOrders: 8, contact: 'sarah@acmecorp.com' },
  { id: 'SUP003', name: 'Global Parts', onTimeDeliveryRate: 85, avgDeliveryTime: 7, recentOrders: 5, contact: 'mike@globalparts.com' },
];

export const mockAlerts: Alert[] = [
  { id: 'ALE001', type: 'Low Stock', item: 'XYZ Cleaner', message: 'Quantity is below threshold (150/200)', date: '2023-10-26', resolved: false },
  { id: 'ALE002', type: 'Reorder', item: 'Heavy-Duty Gloves', message: 'Predicted stockout in 7 days.', date: '2023-10-25', resolved: false },
  { id: 'ALE003', name: 'Obsolete Part X', item: 'Obsolete Part X', message: 'Item has not sold in over 90 days.', date: '2023-10-24', resolved: true },
];

export const mockInventoryValueByCategory: InventoryValueByCategory[] = [
    { category: 'Cleaning', value: 250000 },
    { category: 'Safety', value: 180000 },
    { category: 'Tools', value: 320000 },
    { category: 'Parts', value: 450000 },
    { category: 'General', value: 80000 },
]

export const mockInventoryTrend: InventoryTrend[] = [
    { date: 'Jan', value: 1.1 },
    { date: 'Feb', value: 1.15 },
    { date: 'Mar', value: 1.2 },
    { date: 'Apr', value: 1.18 },
    { date: 'May', value: 1.25 },
    { date: 'Jun', value: 1.3 },
]
