
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getDashboardMetrics } from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { DashboardMetricsSchema } from '@/types';
import { randomUUID } from 'crypto';

// Mock the Supabase client
vi.mock('@/lib/supabase/admin');
vi.mock('@/lib/error-handler');

// ✅ Correct: Use a valid UUID in the test data and all required fields
const mockDashboardData = {
  total_revenue: 100000,
  revenue_change: 10.5,
  total_orders: 50,
  orders_change: 5.2,
  new_customers: 10,
  customers_change: 2.1,
  dead_stock_value: 5000,
  sales_over_time: [{ date: '2024-01-01T00:00:00Z', revenue: 5000 }],
  top_products: [{ product_id: randomUUID(), product_name: 'Test Product', total_revenue: 20000, image_url: null, quantity_sold: 10 }],
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
    supabaseMock = {
        rpc: vi.fn(),
    };
    (getServiceRoleClient as vi.Mock).mockReturnValue(supabaseMock);
    vi.clearAllMocks();
  });

  describe('getDashboardMetrics', () => {
    it('should call the correct RPC function and return data', async () => {
      // ✅ Correct: Mock the rpc call to return the expected structure
      (supabaseMock.rpc as vi.Mock).mockResolvedValue({ 
        data: mockDashboardData, 
        error: null 
      });

      const result = await getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d');

      expect(supabaseMock.rpc).toHaveBeenCalledWith('get_dashboard_metrics', {
        p_company_id: 'd1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a',
        p_days: 30,
      });

      // Validate the result against the Zod schema to ensure correctness
      expect(DashboardMetricsSchema.safeParse(result).success).toBe(true);
      expect(result.total_revenue).toBe(100000);
      expect(result.top_products[0].product_name).toBe('Test Product');
    });

    it('should throw an error if the RPC call fails', async () => {
      const dbError = new Error('Database connection error');
      (supabaseMock.rpc as vi.Mock).mockResolvedValue({ 
        data: null, 
        error: dbError 
      });
      
      await expect(getDashboardMetrics('d1a3c5b9-2d7f-4b8e-9c1a-8b7c6d5e4f3a', '30d')).rejects.toThrow('Could not retrieve dashboard metrics from the database.');
    });
  });
});
