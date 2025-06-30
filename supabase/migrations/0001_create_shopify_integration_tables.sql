-- supabase/migrations/0001_create_shopify_integration_tables.sql

-- ========= Part 1: Integrations Table =========
-- Stores connection details for third-party platforms like Shopify.
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL, -- e.g., 'shopify'
    shop_domain TEXT NOT NULL,
    access_token TEXT NOT NULL, -- Stores the encrypted access token
    shop_name TEXT,
    is_active BOOLEAN DEFAULT true,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    sync_status TEXT, -- e.g., 'syncing', 'success', 'failed'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_integration_per_company UNIQUE (company_id, platform, shop_domain)
);

CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- ========= Part 2: Sync Logs Table =========
-- Tracks the history and outcome of each synchronization attempt.
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL, -- e.g., 'products', 'orders'
    status TEXT NOT NULL, -- 'started', 'completed', 'failed'
    records_synced INTEGER,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_sync_logs_integration_id ON public.sync_logs(integration_id);

-- ========= Part 3: Add Shopify IDs to Existing Tables =========
-- Adds columns to link existing records back to their Shopify source.
-- This is crucial for preventing duplicates and enabling two-way sync in the future.

ALTER TABLE public.inventory
ADD COLUMN IF NOT EXISTS shopify_product_id BIGINT,
ADD COLUMN IF NOT EXISTS shopify_variant_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_inventory_shopify_ids ON public.inventory(company_id, shopify_product_id, shopify_variant_id);

ALTER TABLE public.orders
ADD COLUMN IF NOT EXISTS shopify_order_id BIGINT;

CREATE INDEX IF NOT EXISTS idx_orders_shopify_id ON public.orders(company_id, shopify_order_id);
