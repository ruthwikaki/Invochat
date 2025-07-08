

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

export type SyncLog = {
  id: string;
  integration_id: string;
  sync_type: 'products' | 'sales';
  status: 'started' | 'completed' | 'failed';
  records_synced: number | null;
  error_message: string | null;
  started_at: string;
  completed_at: string | null;
};
