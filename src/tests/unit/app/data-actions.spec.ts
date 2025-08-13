import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getDashboardData } from '@/app/data-actions';
import * as database from '@/services/database';
import type { DashboardMetrics } from '@/types';
import * as authHelpers from '@/lib/auth-helpers';

// Mock dependencies
vi.mock('@/services/database');
vi.mock('@/lib/redis', () => ({
  isRedisEnabled: false, // Ensure cache is disabled for these tests
  redisClient: {},
}));
vi.mock('@/lib/auth-helpers');

const mockDashboardMetrics: DashboardMetrics = {
  total_revenue: 12500000,
  revenue_change: 15.2,
  total_orders: 842,
  orders_change: 8.1,
  new_customers: 120,
  customers_change: -5.5,
  dead_stock_value: 850000,
  sales_over_time: [{ date: '2024-01-01', revenue: 50000 }],
  top_products: [{ product_id: 'p1', product_name: 'Super Widget', total_revenue: 250000, image_url: null, quantity_sold: 10 }],
  inventory_summary: {
    total_value: 50000000,
    in_stock_value: 40000000,
    low_stock_value: 8000000,
    dead_stock_value: 2000000,
  },
};

describe('Server Actions: getDashboardData', () => {

  beforeEach(() => {
    vi.resetAllMocks();
    // Mock the auth context to always return a valid user/company
    (authHelpers.getAuthContext as any).mockResolvedValue({
        userId: 'test-user-id',
        companyId: 'test-company-id'
    });
  });

  it('should fetch and return dashboard metrics successfully', async () => {
    // Arrange: Mock the database function to return our test data
    (database.getDashboardMetrics as any).mockResolvedValue(mockDashboardMetrics);

    // Act: Call the server action
    const result = await getDashboardData('90d');

    // Assert: Verify the database function was called with correct parameters
    expect(database.getDashboardMetrics).toHaveBeenCalledWith('test-company-id', '90d');
    
    // Assert: Verify the result matches the mocked data
    expect(result.total_revenue).toBe(12500000);
    expect(result.top_products[0].product_name).toBe('Super Widget');
  });

  it('should return empty metrics if the database call fails', async () => {
    // Arrange: Mock the database function to reject with an error
    const dbError = new Error('Database connection failed');
    (database.getDashboardMetrics as any).mockRejectedValue(dbError);

    // Act & Assert: Expect the server action to return a default empty object
    const result = await getDashboardData('90d');
    expect(result.total_revenue).toBe(0);
    expect(result.top_products).toEqual([]);
  });
});



