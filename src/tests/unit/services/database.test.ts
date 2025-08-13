
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getDashboardData } from '@/app/data-actions';
import * as database from '@/services/database';

// Mock the Supabase client
vi.mock('@/lib/supabase/admin', () => ({
  getServiceRoleClient: vi.fn(() => ({
    rpc: vi.fn(),
  })),
}));

vi.mock('@/lib/auth-helpers', () => ({
    getAuthContext: vi.fn(() => ({
        companyId: 'test-company-id'
    }))
}))

const mockDashboardData = {
  total_revenue: 100000,
  revenue_change: 10.5,
  total_orders: 50,
  orders_change: 5.2,
  new_customers: 10,
  customers_change: 2.1,
  dead_stock_value: 5000,
  sales_over_time: [{ date: '2024-01-01', revenue: 5000 }],
  top_products: [{ product_id: 'p1', product_name: 'Test Product', total_revenue: 20000, image_url: null, quantity_sold: 10 }],
  inventory_summary: {
    total_value: 200000,
    in_stock_value: 150000,
    low_stock_value: 30000,
    dead_stock_value: 20000,
  },
};

describe('Database Service - Business Logic', () => {
  beforeEach(() => {
    vi.clearAllMocks(); // Reset mocks before each test
  });

  it('getDashboardMetrics should call the correct RPC function and return data', async () => {
    (database.getDashboardMetrics as any).mockResolvedValue(mockDashboardData);

    const result = await getDashboardData('30d');

    expect(database.getDashboardMetrics).toHaveBeenCalledWith('test-company-id', '30d');

    expect(result.total_revenue).toBe(100000);
    expect(result.top_products[0].product_name).toBe('Test Product');
  });

  it('getDashboardMetrics should throw an error if the RPC call fails', async () => {
    const dbError = new Error('Database connection error');
    
    (database.getDashboardMetrics as any).mockRejectedValue(dbError);
    
    await expect(getDashboardData('30d')).rejects.toThrow('Could not retrieve dashboard metrics from the database.');
  });
});
