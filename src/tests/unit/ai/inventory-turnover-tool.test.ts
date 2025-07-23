
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getInventoryTurnoverReport } from '@/ai/flows/inventory-turnover-tool';
import * as database from '@/services/database';

vi.mock('@/services/database');
vi.mock('@/ai/genkit', () => ({
  ai: {
    defineTool: vi.fn((config, func) => ({ ...config, func })),
  },
}));

const mockTurnoverData = {
    turnover_rate: 4.5,
    total_cogs: 5000000,
    average_inventory_value: 1111111,
    period_days: 90
};

describe('Inventory Turnover Tool', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('should return an inventory turnover report from the database', async () => {
    vi.spyOn(database, 'getInventoryTurnoverFromDB').mockResolvedValue(mockTurnoverData);

    const input = { companyId: 'test-company-id', days: 90 };
    const result = await getInventoryTurnoverReport.func(input);

    expect(database.getInventoryTurnoverFromDB).toHaveBeenCalledWith(input.companyId, input.days);
    expect(result).toEqual(mockTurnoverData);
    expect(result.turnover_rate).toBe(4.5);
  });

  it('should throw an error if the database call fails', async () => {
    const dbError = new Error('Database connection failed');
    vi.spyOn(database, 'getInventoryTurnoverFromDB').mockRejectedValue(dbError);

    const input = { companyId: 'test-company-id', days: 90 };

    await expect(getInventoryTurnoverReport.func(input)).rejects.toThrow('An error occurred while trying to calculate the inventory turnover rate.');
  });
});
