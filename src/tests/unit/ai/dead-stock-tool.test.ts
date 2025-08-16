import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getDeadStockReport } from '@/ai/flows/dead-stock-tool';
import * as database from '@/services/database';

vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    defineTool: vi.fn((_config, func) => ({ ..._config, run: func })),
  },
}));

const mockDeadStockData = {
  deadStockItems: [
    {
      sku: 'DS001',
      product_name: 'Old T-Shirt',
      quantity: 100,
      total_value: 50000,
      last_sale_date: new Date('2023-01-01').toISOString(),
    },
  ],
  totalValue: 50000,
  totalUnits: 100,
};

describe('Dead Stock Tool', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should return a list of dead stock items from the database', async () => {
    (database.getDeadStockReportFromDB as any).mockResolvedValue(mockDeadStockData);

    const input = { companyId: 'test-company-id' };
    const result = await (getDeadStockReport as any).run(input);

    expect(database.getDeadStockReportFromDB).toHaveBeenCalledWith(input.companyId);
    expect(result).toEqual(mockDeadStockData);
    expect(result.deadStockItems).toHaveLength(1);
    expect(result.deadStockItems[0].sku).toBe('DS001');
  });

  it('should return an empty array if no dead stock is found', async () => {
    const emptyMockData = {
      deadStockItems: [],
      totalValue: 0,
      totalUnits: 0,
    };
    (database.getDeadStockReportFromDB as any).mockResolvedValue(emptyMockData);

    const input = { companyId: 'test-company-id' };
    const result = await (getDeadStockReport as any).run(input);

    expect(result).toEqual(emptyMockData);
    expect(result.deadStockItems).toHaveLength(0);
  });

  it('should throw an error if the database call fails', async () => {
    const dbError = new Error('Database connection failed');
    (database.getDeadStockReportFromDB as any).mockRejectedValue(dbError);

    const input = { companyId: 'test-company-id' };

    await expect((getDeadStockReport as any).run(input)).rejects.toThrow('An error occurred while trying to generate the dead stock report.');
  });
});




