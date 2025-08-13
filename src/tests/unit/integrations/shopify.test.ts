

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runShopifyFullSync } from '@/features/integrations/services/platforms/shopify';
import * as encryption from '@/features/integrations/services/encryption';
import * as database from '@/services/database';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { Integration } from '@/types';
import * as redis from '@/lib/redis';

// Mock fetch globally
global.fetch = vi.fn();

function createFetchResponse(data: any, linkHeader: string | null = null) {
  const headers = new Headers({ 'Content-Type': 'application/json' });
  if (linkHeader) {
    headers.set('Link', linkHeader);
  }
  return { ok: true, json: () => new Promise((resolve) => resolve(data)), headers };
}

vi.mock('@/features/integrations/services/encryption');
vi.mock('@/services/database');
vi.mock('@/lib/supabase/admin');
vi.mock('@/lib/redis');

const mockIntegration: Integration = {
  id: 'shopify-integration-id',
  company_id: 'test-company-id',
  platform: 'shopify',
  shop_name: 'Test Shopify Store',
  shop_domain: 'test-shop.myshopify.com',
  is_active: true,
  sync_status: 'idle',
  last_sync_at: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const mockShopifyProducts = {
  products: [
    { id: 1, title: 'Product 1', variants: [{ id: 101, sku: 'P1V1', price: '10.00', option1: 'Small' }], tags: 'tag1, tag2', options: [{name: 'Size'}] },
    { id: 2, title: 'Product 2', variants: [{ id: 102, sku: 'P2V1', price: '20.00', option1: 'Large' }], tags: null, options: [{name: 'Size'}] },
  ],
};

const mockShopifyOrders = {
  orders: [{ id: 1001, total_price: '10.00', line_items: [{ sku: 'P1V1', quantity: 1 }] }],
};

describe('Shopify Integration Service', () => {
  let supabaseMock: any;

  beforeEach(() => {
    vi.resetAllMocks();
    (fetch as any).mockClear();

    supabaseMock = {
        from: vi.fn().mockReturnThis(),
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        upsert: vi.fn(() => ({ select: vi.fn().mockResolvedValue({ data: [{id: 'prod-id', external_product_id: '1'}], error: null }) })),
        rpc: vi.fn().mockResolvedValue({ error: null }),
    };
    (getServiceRoleClient as any).mockReturnValue(supabaseMock);
    vi.spyOn(encryption, 'getSecret').mockResolvedValue('shpat_test_token');
    vi.spyOn(redis, 'invalidateCompanyCache').mockResolvedValue(undefined);
    vi.spyOn(database, 'refreshMaterializedViews').mockResolvedValue(undefined);
  });

  it('should run a full sync successfully', async () => {
    (fetch as any)
      .mockResolvedValueOnce(createFetchResponse(mockShopifyProducts)) // products fetch
      .mockResolvedValueOnce(createFetchResponse(mockShopifyOrders));  // orders fetch

    await runShopifyFullSync(mockIntegration);

    expect(encryption.getSecret).toHaveBeenCalledWith(mockIntegration.company_id, 'shopify');
    expect(fetch).toHaveBeenCalledTimes(2);

    // Verify product and order sync logic was called
    expect(supabaseMock.upsert).toHaveBeenCalled();
    expect(supabaseMock.rpc).toHaveBeenCalledWith('record_order_from_platform', expect.anything());

    // Verify status updates
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'syncing_products' });
    expect(supabaseMock.update).toHaveBeenCalledWith({ sync_status: 'syncing_sales' });
    expect(supabaseMock.update).toHaveBeenCalledWith(expect.objectContaining({ sync_status: 'success' }));
    
    // Verify post-sync actions
    expect(redis.invalidateCompanyCache).toHaveBeenCalled();
    expect(database.refreshMaterializedViews).toHaveBeenCalled();
  });

  it('should handle pagination for products', async () => {
    const linkHeader = '<https://test-shop.myshopify.com/admin/api/2024-07/products.json?page_info=nextPageToken>; rel="next"';
    (fetch as any)
      .mockResolvedValueOnce(createFetchResponse(mockShopifyProducts, linkHeader)) // first page
      .mockResolvedValueOnce(createFetchResponse(mockShopifyProducts)) // second page (no link header)
      .mockResolvedValueOnce(createFetchResponse(mockShopifyOrders)); // orders
      
    await runShopifyFullSync(mockIntegration);

    expect(fetch).toHaveBeenCalledTimes(3); // 2 for products, 1 for orders
  });

  it('should throw an error if fetching products fails', async () => {
    (fetch as any).mockResolvedValueOnce({ ok: false, status: 500, text: () => Promise.resolve('Server Error') });
    await expect(runShopifyFullSync(mockIntegration)).rejects.toThrow('Shopify API product fetch error (500): Server Error');
  });
});




