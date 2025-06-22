import type { ReactNode } from 'react';

export type Message = {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: ReactNode;
  timestamp: number;
};

export type AssistantMessagePayload = {
  id: string;
  role: 'assistant';
  content?: string;
  component?: 'DeadStockTable' | 'SupplierPerformanceTable' | 'ReorderList';
  props?: any;
};

// New types for pages
export type InventoryItem = {
    id: string;
    name: string;
    quantity: number;
    value: number;
    lastSold: string;
    category?: string;
    warehouse?: string;
}

export type DeadStockItem = {
    id: string;
    name: string;
    quantity: number;
    value: number;
    lastSold: string;
    reason: string;
}

export type Supplier = {
    id: string;
    name: string;
    onTimeDeliveryRate: number;
    avgDeliveryTime: number;
    recentOrders: number;
    contact: string;
}

export type Alert = {
    id: string;
    type: 'Low Stock' | 'Reorder' | 'Dead Stock';
    item: string;
    message: string;
    date: string;
    resolved: boolean;
    name?: string;
}

export type InventoryValueByCategory = {
    category: string;
    value: number;
}

export type InventoryTrend = {
    date: string;
    value: number;
}
