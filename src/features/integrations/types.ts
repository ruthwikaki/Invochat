
export type ShopifyIntegration = {
  id: string;
  company_id: string;
  platform: 'shopify';
  shop_domain: string;
  shop_name: string | null;
  is_active: boolean;
  last_sync_at: string | null;
  sync_status: 'syncing' | 'success' | 'failed' | 'idle' | null;
  created_at: string;
};

export type SyncLog = {
  id: string;
  integration_id: string;
  sync_type: 'products' | 'orders';
  status: 'started' | 'completed' | 'failed';
  records_synced: number | null;
  error_message: string | null;
  started_at: string;
  completed_at: string | null;
};

export type ShopifyConnectPayload = {
    storeUrl: string;
    accessToken: string;
};
