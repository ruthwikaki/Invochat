
import type { ReactNode } from 'react';

export type Message = {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: ReactNode;
  timestamp: number;
};

// Represents the configuration for a dynamically generated chart.
export type ChartConfig = {
    chartType: 'bar' | 'pie' | 'line';
    title: string;
    data: any[];
    config: {
        dataKey: string;
        nameKey?: string;
        fill?: string;
        stroke?: string;
        // For line/bar charts
        xAxisKey?: string;
        // For pie charts
        innerRadius?: number;
        outerRadius?: number;
        paddingAngle?: number;
    }
}

export type AssistantMessagePayload = {
  id: string;
  role: 'assistant';
  content?: string;
  component?: 'DeadStockTable' | 'SupplierPerformanceTable' | 'ReorderList' | 'DynamicChart';
  props?: any;
};

// Data models based on database schema
export type Warehouse = {
    id: number;
    name: string;
    location: string;
};

export type Supplier = {
    id: number;
    name: string;
    onTimeDeliveryRate: number;
    avgDeliveryTime: number;
    contact: string;
}

export type Product = {
    id: string; // UUID
    company_id: string; // UUID
    sku: string;
    name: string;
    category: string;
    quantity: number;
    cost: number;
    price: number;
    warehouse_id?: string; // UUID
    last_sold_date?: string; // ISO String
}

export type Transaction = {
    id: number;
    product_id: number;
    type: 'sale' | 'purchase';
    quantity: number;
    date: string; // YYYY-MM-DD
    amount: number;
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

export type InventoryItem = {
    id: string; // SKU
    name: string;
    quantity: number;
    value: number;
    lastSold: string;
}

export type InventoryValueByCategory = {
    category: string;
    value: number;
}

export type InventoryTrend = {
    date: string;
    value: number;
}

export type DashboardMetrics = {
    inventoryValue: number;
    deadStockValue: number;
    lowStockItems: number;
    onTimeDeliveryRate: number; // This is now a placeholder
    predictiveAlert: {
        item: string;
        days: number;
    } | null;
}

// User profile from Supabase, including company info
export type UserProfile = {
  id: string; // Firebase UID
  email: string;
  role: 'admin' | 'member' | string;
  companyId: string;
  company?: {
    id: string;
    name: string;
  };
};
