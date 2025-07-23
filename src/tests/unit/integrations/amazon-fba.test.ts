
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runAmazonFbaFullSync } from '@/features/integrations/services/platforms/amazon_fba';
import * as encryption from '@/features/integrations/services/encryption';
import * as database from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Integration } from '@/types';

// Mock dependencies
vi.mock('@/features/integrations/services/encryption');
vi.mock('@/services/database');
vi.mock('@/lib/supabase/admin');

const mockIntegration: Integration = {
  id: 'fba-integration-id',
  company_id: 'test-company-id',
  platform: 'amazon_fba',
  shop_name: 'Test FBA Store',
  shop_domain: null,
  is_active: true,
  sync_status: 'idle',
  last_sync_at: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const mockCredentials = { sellerId: 'AMZN123', authToken: 'TOKENABC' };

describe('Amazon FBA Integration Service', () => {
  let supabaseMock: any;
  let updateMock: any;

  beforeEach(() => {
    vi.resetAllMocks();
    updateMock = vi.fn().mockReturnThis();
    supabaseMock = {
      from: vi.fn(() => ({
        update: updateMock,
        eq: vi.fn().mockReturnThis()
      })),
      rpc: vi.fn().mockResolvedValue({ error: null }),
    };
    (getServiceRoleClient as vi.Mock).mockReturnValue(supabaseMock);
    vi.spyOn(encryption, 'getSecret').mockResolvedValue(JSON.stringify(mockCredentials));
    vi.spyOn(database, 'invalidateCompanyCache').mockResolvedValue();
    vi.spyOn(database, 'refreshMaterializedViews').mockResolvedValue();
  });

  it('should run a full sync simulation successfully', async () => {
    await runAmazonFbaFullSync(mockIntegration);

    // Check that credentials were retrieved
    expect(encryption.getSecret).toHaveBeenCalledWith(mockIntegration.company_id, 'amazon_fba');
    
    // Check that sync status was updated multiple times
    expect(updateMock).toHaveBeenCalledWith({ sync_status: 'syncing_products' });
    expect(updateMock).toHaveBeenCalledWith({ sync_status: 'syncing_sales' });
    expect(updateMock).toHaveBeenCalledWith(expect.objectContaining({ sync_status: 'success' }));
    
    // Check that sales data was recorded via RPC
    expect(supabaseMock.rpc).toHaveBeenCalledWith(
        'record_order_from_platform', 
        expect.objectContaining({ p_platform: 'amazon_fba' })
    );

    // Check that caches were invalidated and views refreshed
    expect(database.invalidateCompanyCache).toHaveBeenCalled();
    expect(database.refreshMaterializedViews).toHaveBeenCalled();
  });

  it('should handle credential retrieval failure', async () => {
    vi.spyOn(encryption, 'getSecret').mockResolvedValue(null);

    await expect(runAmazonFbaFullSync(mockIntegration)).rejects.toThrow('Could not retrieve Amazon FBA credentials.');
    expect(updateMock).toHaveBeenCalledWith({ sync_status: 'failed' });
  });

   it('should handle database errors during sync', async () => {
    const dbError = new Error('RPC call failed');
    supabaseMock.rpc.mockResolvedValue({ error: dbError });

    await expect(runAmazonFbaFullSync(mockIntegration)).rejects.toThrow('RPC call failed');
    expect(updateMock).toHaveBeenCalledWith({ sync_status: 'failed' });
  });
});
