
import { describe, it, expect, vi } from 'vitest';
import { getDashboardMetrics } from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// Mock the Supabase client
vi.mock('@/lib/supabase/admin', () => ({
  getServiceRoleClient: vi.fn(() => ({
    rpc: vi.fn(),
  })),
}));

const mockDashboardData = {
  total_revenue: 100000,
  revenue_change: 10.5,
  total_sales: 50,
  sales_change: 5.2,
  new_customers: 10,
  customers_change: 2.1,
  dead_stock_value: 5000,
  sales_over_time: [{ date: '2024-01-01', total_sales: 5000 }],
  top_selling_products: [{ product_name: 'Test Product', total_revenue: 20000, image_url: null }],
  inventory_summary: {
    total_value: 200000,
    in_stock_value: 150000,
    low_stock_value: 30000,
    dead_stock_value: 20000,
  },
};

describe('Database Service - Business Logic', () => {
  it('getDashboardMetrics should call the correct RPC function and return data', async () => {
    const supabaseMock = getServiceRoleClient();
    (supabaseMock.rpc as vi.Mock).mockResolvedValue({ data: mockDashboardData, error: null });

    const result = await getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d');

    expect(supabaseMock.rpc).toHaveBeenCalledWith('get_dashboard_metrics', {
      p_company_id: 'd1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a',
      p_days: 30,
    });

    expect(result.total_revenue).toBe(100000);
    expect(result.top_selling_products[0].product_name).toBe('Test Product');
  });

   it('getDashboardMetrics should throw an error if the RPC call fails', async () => {
    const supabaseMock = getServiceRoleClient();
    const dbError = new Error('Database connection error');
    (supabaseMock.rpc as vi.Mock).mockResolvedValue({ data: null, error: dbError });

    await expect(getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d')).rejects.toThrow('Could not retrieve dashboard metrics from the database.');
  });
});
