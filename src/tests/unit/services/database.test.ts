import { describe, it, expect, vi, beforeEach } from 'vitest';
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
  let supabaseMock: any;

  beforeEach(() => {
    supabaseMock = getServiceRoleClient();
    vi.clearAllMocks(); // Reset mocks before each test
  });

  it('getDashboardMetrics should call the correct RPC function and return data', async () => {
    // Mock successful response with proper structure
    (supabaseMock.rpc as any).mockResolvedValue({ 
      data: mockDashboardData, 
      error: null 
    });

    const result = await getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d');

    expect(supabaseMock.rpc).toHaveBeenCalledWith('get_dashboard_metrics', {
      p_company_id: 'd1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a',
      p_days: 30,
    });

    expect(result.total_revenue).toBe(100000);
    expect(result.top_products[0].product_name).toBe('Test Product');
  });

  it('getDashboardMetrics should throw an error if the RPC call fails', async () => {
    const dbError = { message: 'Database connection error' };
    
    (supabaseMock.rpc as any).mockResolvedValue({ 
      data: null, 
      error: dbError 
    });

    await expect(getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d')).rejects.toThrow('Could not retrieve dashboard metrics from the database.');
  });

  it('getDashboardMetrics should throw an error if data is null but no error object', async () => {
    // Simulate response with null data but no error (edge case)
    (supabaseMock.rpc as any).mockResolvedValue({ 
      data: null, 
      error: null 
    });
    
    await expect(getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d')).rejects.toThrow('No response from get_dashboard_metrics RPC call.');
  });
});




