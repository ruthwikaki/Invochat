

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runAmazonFbaFullSync } from '@/features/integrations/services/platforms/amazon_fba';
import * as encryption from '@/features/integrations/services/encryption';
import * as database from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Integration } from '@/types';
import * as redis from '@/lib/redis';

// Mock dependencies
vi.mock('@/features/integrations/services/encryption');
vi.mock('@/services/database');
vi.mock('@/lib/supabase/admin');
vi.mock('@/lib/redis');

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

  beforeEach(() => {
    vi.resetAllMocks();
    
    supabaseMock = {
      from: vi.fn().mockReturnThis(),
      update: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      rpc: vi.fn().mockResolvedValue({ error: null }),
    };
    (getServiceRoleClient as any).mockReturnValue(supabaseMock);
    
    vi.spyOn(encryption, 'getSecret').mockResolvedValue(JSON.stringify(mockCredentials));
    vi.spyOn(redis, 'invalidateCompanyCache').mockResolvedValue(undefined);
    vi.spyOn(database, 'refreshMaterializedViews').mockResolvedValue(undefined);
  });

  it('should run a full sync simulation successfully', async () => {
    await runAmazonFbaFullSync(mockIntegration);

    expect(encryption.getSecret).toHaveBeenCalledWith(mockIntegration.company_id, 'amazon_fba');
    
    expect(supabaseMock.from).toHaveBeenCalledWith('integrations');
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'syncing_products' });
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'syncing_sales' });
    expect(supabaseMock.update).toHaveBeenCalledWith(expect.objectContaining({ sync_status: 'success' }));
    
    expect(supabaseMock.rpc).toHaveBeenCalledWith(
        'record_order_from_platform', 
        expect.objectContaining({ p_platform: 'amazon_fba' })
    );

    expect(redis.invalidateCompanyCache).toHaveBeenCalled();
    expect(database.refreshMaterializedViews).toHaveBeenCalled();
  });

  it('should handle credential retrieval failure', async () => {
    vi.spyOn(encryption, 'getSecret').mockResolvedValue(null);

    await expect(runAmazonFbaFullSync(mockIntegration)).rejects.toThrow('Could not retrieve Amazon FBA credentials.');
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'failed' });
  });

   it('should handle database errors during sync', async () => {
    const dbError = new Error('RPC call failed');
    supabaseMock.rpc.mockRejectedValue(dbError);

    await expect(runAmazonFbaFullSync(mockIntegration)).rejects.toThrow(dbError);
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'failed' });
  });
});


