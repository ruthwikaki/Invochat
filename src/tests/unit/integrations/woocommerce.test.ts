
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runWooCommerceFullSync } from '@/features/integrations/services/platforms/woocommerce';
import * as encryption from '@/features/integrations/services/encryption';
import * as database from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Integration } from '@/types';

// Mock fetch globally
global.fetch = vi.fn();

function createFetchResponse(data: any, totalPages = 1) {
  const headers = new Headers({ 
      'Content-Type': 'application/json',
      'X-WP-TotalPages': String(totalPages)
    });
  return { ok: true, json: () => new Promise((resolve) => resolve(data)), headers };
}

vi.mock('@/features/integrations/services/encryption');
vi.mock('@/services/database');
vi.mock('@/lib/supabase/admin');

const mockIntegration: Integration = {
  id: 'woo-integration-id',
  company_id: 'test-company-id',
  platform: 'woocommerce',
  shop_name: 'Test Woo Store',
  shop_domain: 'https://test-shop.com',
  is_active: true,
  sync_status: 'idle',
  last_sync_at: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const mockCredentials = { consumerKey: 'ck_test', consumerSecret: 'cs_test' };

const mockWooProducts = [
  { id: 1, name: 'Simple Product', type: 'simple', sku: 'SIMPLE1', price: '20.00', stock_quantity: 10 },
  { id: 2, name: 'Variable Product', type: 'variable', sku: 'VAR1' }
];

const mockWooVariations = [
  { id: 3, parent_id: 2, sku: 'VAR1-S', price: '25.00', stock_quantity: 5, attributes: [{ name: 'Size', option: 'Small'}] },
];

const mockWooOrders = [
  { id: 101, total: '20.00', line_items: [{ sku: 'SIMPLE1', quantity: 1 }] }
];

describe('WooCommerce Integration Service', () => {
  let supabaseMock: any;

  beforeEach(() => {
    vi.resetAllMocks();
    (fetch as vi.Mock).mockClear();

    supabaseMock = {
      from: vi.fn(() => ({
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        upsert: vi.fn(() => ({ select: vi.fn().mockResolvedValue({ data: [{id: 'prod-id-1', external_product_id: '1'}, {id: 'prod-id-2', external_product_id: '2'}], error: null }) })),
      })),
      rpc: vi.fn().mockResolvedValue({ error: null }),
    };
    (getServiceRoleClient as vi.Mock).mockReturnValue(supabaseMock);
    vi.spyOn(encryption, 'getSecret').mockResolvedValue(JSON.stringify(mockCredentials));
    vi.spyOn(database, 'invalidateCompanyCache').mockResolvedValue();
    vi.spyOn(database, 'refreshMaterializedViews').mockResolvedValue();
  });

  it('should run a full sync successfully', async () => {
    (fetch as vi.Mock)
      .mockResolvedValueOnce(createFetchResponse(mockWooProducts)) // products fetch
      .mockResolvedValueOnce(createFetchResponse(mockWooVariations)) // variations fetch
      .mockResolvedValueOnce(createFetchResponse(mockWooOrders));   // orders fetch

    await runWooCommerceFullSync(mockIntegration);

    expect(encryption.getSecret).toHaveBeenCalledWith(mockIntegration.company_id, 'woocommerce');
    expect(fetch).toHaveBeenCalledTimes(3);

    // Verify variant and product upserts
    expect(supabaseMock.from('products').upsert).toHaveBeenCalled();
    expect(supabaseMock.from('product_variants').upsert).toHaveBeenCalled();
    
    // Check that both simple and variable product variants were processed
    const upsertedVariants = supabaseMock.from('product_variants').upsert.mock.calls[0][0];
    expect(upsertedVariants.find((v: any) => v.sku === 'SIMPLE1')).toBeDefined();
    expect(upsertedVariants.find((v: any) => v.sku === 'VAR1-S')).toBeDefined();

    // Verify status updates
    expect(supabaseMock.from('integrations').update).toHaveBeenCalledWith({ sync_status: 'syncing_products' });
    expect(supabaseMock.from('integrations').update).toHaveBeenCalledWith({ sync_status: 'syncing_sales' });
    expect(supabaseMock.from('integrations').update).toHaveBeenCalledWith(expect.objectContaining({ sync_status: 'success' }));
  });

  it('should throw an error if credentials are not found', async () => {
     vi.spyOn(encryption, 'getSecret').mockResolvedValue(null);
     await expect(runWooCommerceFullSync(mockIntegration)).rejects.toThrow('WooCommerce credentials are missing.');
  });
});
