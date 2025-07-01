import React from 'react';
import { render, screen } from '@testing-library/react';
import { BusinessHealthScore } from '../business-health-score';
import type { DashboardMetrics } from '@/types';

// Mock dependencies
jest.mock('framer-motion', () => ({
  ...jest.requireActual('framer-motion'),
  motion: {
    div: ({ children, ...props }: { children: React.ReactNode }) => <div {...props}>{children}</div>,
  },
  useInView: () => true, // Mock useInView to always be true for animations
}));

jest.mock('recharts', () => ({
  ...jest.requireActual('recharts'),
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div data-testid="recharts-container">{children}</div>,
  PieChart: ({ children }: { children: React.ReactNode }) => <div data-testid="pie-chart">{children}</div>,
  Pie: () => <div data-testid="pie" />,
  Cell: () => null,
  Tooltip: () => null,
}));

// Test data
const excellentMetrics: DashboardMetrics = {
  totalSkus: 100,
  deadStockItemsCount: 5,
  lowStockItemsCount: 2,
  totalSalesValue: 100000,
  totalProfit: 40000, // 40% margin
  salesTrendData: [{ date: '1', Sales: 100 }, { date: '2', Sales: 200 }], // Positive slope
  // Other fields are not used in this component's calculation
  returnRate: 0,
  totalInventoryValue: 0,
  totalOrders: 0,
  totalCustomers: 0,
  averageOrderValue: 0,
  inventoryByCategoryData: [],
  topCustomersData: [],
};

const goodMetrics: DashboardMetrics = {
  totalSkus: 100,
  deadStockItemsCount: 15,
  lowStockItemsCount: 10,
  totalSalesValue: 100000,
  totalProfit: 25000, // 25% margin
  salesTrendData: [{ date: '1', Sales: 100 }, { date: '2', Sales: 110 }], // Slightly positive slope
  returnRate: 0,
  totalInventoryValue: 0,
  totalOrders: 0,
  totalCustomers: 0,
  averageOrderValue: 0,
  inventoryByCategoryData: [],
  topCustomersData: [],
};

const poorMetrics: DashboardMetrics = {
  totalSkus: 100,
  deadStockItemsCount: 40, // High dead stock
  lowStockItemsCount: 50, // High low stock
  totalSalesValue: 100000,
  totalProfit: 10000, // 10% margin
  salesTrendData: [{ date: '1', Sales: 200 }, { date: '2', Sales: 100 }], // Negative slope
  returnRate: 0,
  totalInventoryValue: 0,
  totalOrders: 0,
  totalCustomers: 0,
  averageOrderValue: 0,
  inventoryByCategoryData: [],
  topCustomersData: [],
};

describe('BusinessHealthScore', () => {
  it('renders the component title and description', () => {
    render(<BusinessHealthScore metrics={excellentMetrics} />);
    expect(screen.getByText('Business Health Score')).toBeInTheDocument();
    expect(screen.getByText("An AI-powered overview of your key metrics.")).toBeInTheDocument();
  });

  it('calculates and displays an "Excellent" score correctly', () => {
    // Inventory: (1 - 5/100 * 2) * 25 = 22.5
    // Profitability: 25 (margin > 30%)
    // Stock Availability: (1 - 2/100) * 25 = 24.5
    // Sales Growth: 25 (positive slope)
    // Total: 22.5 + 25 + 24.5 + 25 = 97
    render(<BusinessHealthScore metrics={excellentMetrics} />);
    expect(screen.getByText('97')).toBeInTheDocument();
    expect(screen.getByText('Excellent')).toBeInTheDocument();
  });

  it('calculates and displays a "Good" score correctly', () => {
    // Inventory: (1 - 15/100 * 2) * 25 = 17.5
    // Profitability: 15 (margin > 15%)
    // Stock Availability: (1 - 10/100) * 25 = 22.5
    // Sales Growth: 25 (positive slope)
    // Total: 17.5 + 15 + 22.5 + 25 = 80
    render(<BusinessHealthScore metrics={goodMetrics} />);
    expect(screen.getByText('80')).toBeInTheDocument();
    expect(screen.getByText('Good')).toBeInTheDocument();
  });
  
  it('calculates and displays a "Needs Attention" score correctly', () => {
    // Inventory: (1 - 40/100 * 2) * 25 = 5
    // Profitability: 5 (margin < 15%)
    // Stock Availability: (1 - 50/100) * 25 = 12.5
    // Sales Growth: 10 (negative slope)
    // Total: 5 + 5 + 12.5 + 10 = 32.5 -> rounded to 33
    render(<BusinessHealthScore metrics={poorMetrics} />);
    expect(screen.getByText('33')).toBeInTheDocument();
    expect(screen.getByText('Needs Attention')).toBeInTheDocument();
  });

  it('renders the breakdown of scores', () => {
    render(<BusinessHealthScore metrics={excellentMetrics} />);
    expect(screen.getByText('Profitability:')).toBeInTheDocument();
    expect(screen.getByText('Sales Growth:')).toBeInTheDocument();
    expect(screen.getByText('Stock Availability:')).toBeInTheDocument();
    expect(screen.getByText('Inventory Health:')).toBeInTheDocument();
  });

  it('handles edge case where totalSkus is zero to prevent division by zero', () => {
    const zeroSkuMetrics = { ...poorMetrics, totalSkus: 0 };
    render(<BusinessHealthScore metrics={zeroSkuMetrics} />);
    // Health score should still calculate without crashing
    expect(screen.getByText('40')).toBeInTheDocument(); // Profitability(5) + Sales(10) + Inv(0*25=0) + Stock(1*25=25) = 40
  });
});
