
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
export type Vendor = {
    id: string; // UUID
    company_id: string; // UUID
    vendor_name: string;
    address: string;
    contact_info: string;
    terms: string;
}

export type InventoryItem = {
    id: string; // UUID
    company_id: string; // UUID
    sku: string;
    name: string;
    description: string;
    category: string;
    quantity: number;
    cost: number;
    price: number;
    reorder_point: number;
    reorder_qty: number;
    supplier_name: string;
    warehouse_id?: string; // UUID
    last_sold_date?: string; // ISO String
}

export type Alert = {
    id: string;
    type: 'Low Stock';
    item: string;
    message: string;
    date: string;
    resolved: boolean;
}

export type DashboardMetrics = {
    totalProducts: number;
    totalValue: number;
    lowStockItems: number;
    deadStockValue: number;
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
