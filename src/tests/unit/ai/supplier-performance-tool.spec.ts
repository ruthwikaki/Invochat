

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getSupplierPerformanceReport } from '@/ai/flows/supplier-performance-tool';
import * as database from '@/services/database';
import type { SupplierPerformanceReport } from '@/types';

vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    defineTool: vi.fn((_config, func) => ({ ..._config, func })),
  },
}));

const mockPerformanceData: SupplierPerformanceReport[] = [
  {
    supplier_name: 'Supplier A',
    total_profit: 1000000, // in cents
    total_sales_count: 150,
    distinct_products_sold: 10,
    average_margin: 45.5,
    sell_through_rate: 0.85,
    on_time_delivery_rate: 98.2,
    average_lead_time_days: 14,
    total_completed_orders: 20,
  },
];

describe('Supplier Performance Tool', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should return supplier performance data from the database', async () => {
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockResolvedValue(mockPerformanceData);

    const input = { companyId: 'test-company-id' };
    const result = await getSupplierPerformanceReport.run(input);

    expect(database.getSupplierPerformanceFromDB).toHaveBeenCalledWith(input.companyId);
    expect(result).toEqual(mockPerformanceData);
    expect(result[0].supplier_name).toBe('Supplier A');
  });

  it('should return an empty array if no data is available', async () => {
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockResolvedValue([]);
    const input = { companyId: 'test-company-id' };
    const result = await getSupplierPerformanceReport.run(input);
    expect(result).toEqual([]);
  });

  it('should propagate errors from the database layer', async () => {
    const error = new Error('DB Error');
    vi.spyOn(database, 'getSupplierPerformanceFromDB').mockRejectedValue(error);
    const input = { companyId: 'test-company-id' };
    await expect(getSupplierPerformanceReport.run(input)).rejects.toThrow('An error occurred while trying to generate the supplier performance report.');
  });
});




