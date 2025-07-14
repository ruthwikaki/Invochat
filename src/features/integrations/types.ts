// This file is obsolete. All types have been consolidated into /src/types/index.ts.
// It is kept temporarily to prevent breaking existing imports but should be removed.
export type Platform = 'shopify' | 'woocommerce' | 'amazon_fba';

export type Integration = {
  id: string;
  company_id: string;
  platform: Platform;
  shop_domain: string | null;
  shop_name: string | null;
  is_active: boolean;
  last_sync_at: string | null;
  sync_status: 'syncing_products' | 'syncing_sales' | 'syncing' | 'success' | 'failed' | 'idle' | null;
  created_at: string;
  updated_at: string | null;
};
