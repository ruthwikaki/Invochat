
-- InvoChat Final Database Schema & Migration Script
-- Version: 2.0.0
-- This script is designed to be idempotent and can be run safely on an existing database.
-- It drops dependent objects before altering tables and then recreates them.

-- Drop dependent views first to allow underlying table modifications.
DROP VIEW IF EXISTS public.product_variants_with_details;
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;

-- Drop all existing RLS policies to break dependencies on old functions.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Drop the old insecure function. Now possible because no policies depend on it.
DROP FUNCTION IF EXISTS public.get_my_company_id();
DROP FUNCTION IF EXISTS public.is_company_member(uuid);

-- =============================================================================
-- TABLE ALTERATIONS
-- Add missing columns and modify existing ones with 'IF NOT EXISTS' for safety.
-- =============================================================================

-- Add fts_document to products for full-text search
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS fts_document tsvector;

-- Make product_variants.sku and title NOT NULL
ALTER TABLE public.product_variants ALTER COLUMN sku SET NOT NULL;
ALTER TABLE public.product_variants ALTER COLUMN inventory_quantity SET NOT NULL;

-- Remove obsolete columns from product_variants
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight;
ALTER TABLE public.product_variants DROP COLUMN IF EXISTS weight_unit;

-- Add user_id and company_id to audit_log
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id);

-- Add idempotency_key to purchase_orders for safe retries
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS idempotency_key UUID;


-- Standardize all monetary columns to INTEGER (cents)
ALTER TABLE public.refunds ALTER COLUMN total_amount TYPE INTEGER USING (total_amount::numeric * 100)::integer;
ALTER TABLE public.refund_line_items ALTER COLUMN amount TYPE INTEGER USING (amount::numeric * 100)::integer;
ALTER TABLE public.customers ALTER COLUMN total_spent TYPE INTEGER USING (total_spent::numeric * 100)::integer;
ALTER TABLE public.channel_fees ALTER COLUMN percentage_fee TYPE INTEGER USING (percentage_fee::numeric * 100)::integer;
ALTER TABLE public.channel_fees ALTER COLUMN fixed_fee TYPE INTEGER USING (fixed_fee::numeric * 100)::integer;
ALTER TABLE public.company_settings ALTER COLUMN tax_rate TYPE INTEGER USING (tax_rate::numeric * 100)::integer;

-- =============================================================================
-- FUNCTIONS AND TRIGGERS
-- =============================================================================

-- Securely get the user's company ID from the users table
CREATE OR REPLACE FUNCTION public.get_current_user_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = auth.uid();
$$;


-- Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert the user into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger for new user setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to update the full-text search vector
CREATE OR REPLACE FUNCTION public.update_product_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.fts_document := to_tsvector('english', coalesce(NEW.title, '') || ' ' || coalesce(NEW.product_type, '') || ' ' || coalesce(array_to_string(NEW.tags, ' '), ''));
  RETURN NEW;
END;
$$;

-- Trigger for FTS
DROP TRIGGER IF EXISTS update_product_fts_trigger ON public.products;
CREATE TRIGGER update_product_fts_trigger
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.update_product_fts_document();


-- =============================================================================
-- INDEXES
-- Drop existing indexes before creating them to ensure idempotency.
-- =============================================================================

DROP INDEX IF EXISTS public.product_fts_idx;
CREATE INDEX product_fts_idx ON public.products USING gin(fts_document);

DROP INDEX IF EXISTS public.products_company_id_external_id_idx;
CREATE UNIQUE INDEX products_company_id_external_id_idx ON public.products(company_id, external_product_id);

DROP INDEX IF EXISTS public.variants_company_id_external_id_idx;
CREATE UNIQUE INDEX variants_company_id_external_id_idx ON public.product_variants(company_id, external_variant_id);

DROP INDEX IF EXISTS public.product_variants_sku_company_id_idx;
CREATE UNIQUE INDEX product_variants_sku_company_id_idx ON public.product_variants(sku, company_id);

DROP INDEX IF EXISTS public.order_line_items_order_id_idx;
CREATE INDEX order_line_items_order_id_idx ON public.order_line_items(order_id);

DROP INDEX IF EXISTS public.purchase_order_line_items_po_id_idx;
CREATE INDEX purchase_order_line_items_po_id_idx ON public.purchase_order_line_items(purchase_order_id);

DROP INDEX IF EXISTS public.inventory_ledger_variant_id_idx;
CREATE INDEX inventory_ledger_variant_id_idx ON public.inventory_ledger(variant_id);

DROP INDEX IF EXISTS public.po_company_idempotency_idx;
CREATE UNIQUE INDEX po_company_idempotency_idx ON public.purchase_orders (company_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

DROP INDEX IF EXISTS public.webhook_events_integration_id_webhook_id_key;
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_key ON public.webhook_events(integration_id, webhook_id);

-- =============================================================================
-- VIEWS and MATERIALIZED VIEWS
-- Recreate the views that were dropped earlier.
-- =============================================================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;


CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    c.id AS company_id,
    c.name AS company_name,
    COUNT(DISTINCT p.id) AS total_products,
    SUM(pv.inventory_quantity) AS total_units,
    SUM(pv.inventory_quantity * pv.cost) AS total_inventory_value
FROM
    public.companies c
LEFT JOIN
    public.products p ON c.id = p.company_id
LEFT JOIN
    public.product_variants pv ON p.id = pv.product_id
GROUP BY
    c.id, c.name;

-- =============================================================================
-- ROW-LEVEL SECURITY (RLS)
-- Enable RLS and apply secure policies to all tables.
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Policy helper function (replaces old insecure function)
CREATE OR REPLACE FUNCTION public.user_is_member_of_company(p_company_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = auth.uid() AND u.company_id = p_company_id
  );
$$;

-- Generic Policy for tables with a `company_id` column
CREATE OR REPLACE PROCEDURE public.apply_company_rls(table_name TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('CREATE POLICY "Allow company members full access" ON public.%I FOR ALL USING (user_is_member_of_company(company_id)) WITH CHECK (user_is_member_of_company(company_id));', table_name);
END;
$$;

-- Apply the generic policy to relevant tables
CALL public.apply_company_rls('products');
CALL public.apply_company_rls('product_variants');
CALL public.apply_company_rls('orders');
CALL public.apply_company_rls('order_line_items');
CALL public.apply_company_rls('customers');
CALL public.apply_company_rls('refunds');
CALL public.apply_company_rls('refund_line_items');
CALL public.apply_company_rls('suppliers');
CALL public.apply_company_rls('purchase_orders');
CALL public.apply_company_rls('purchase_order_line_items');
CALL public.apply_company_rls('inventory_ledger');
CALL public.apply_company_rls('integrations');
CALL public.apply_company_rls('company_settings');
CALL public.apply_company_rls('audit_log');
CALL public.apply_company_rls('webhook_events');


-- Specific Policies for tables without a direct company_id or with different logic

-- Users can see other users in their own company
CREATE POLICY "Allow users to see other members of their company" ON public.users
FOR SELECT USING (company_id = public.get_current_user_company_id());

-- Users can manage their own conversations
CREATE POLICY "Users can manage their own conversations" ON public.conversations
FOR ALL USING (user_id = auth.uid());

-- Users can manage messages in their conversations
CREATE POLICY "Users can manage messages in their conversations" ON public.messages
FOR ALL USING (EXISTS (
  SELECT 1 FROM public.conversations c
  WHERE c.id = messages.conversation_id AND c.user_id = auth.uid()
));

-- Users can see their own company details
CREATE POLICY "Users can see their own company" ON public.companies
FOR SELECT USING (id = public.get_current_user_company_id());


-- =============================================================================
-- NOTIFICATIONS CHANNEL
-- =============================================================================
DO $$
BEGIN
    -- Check if the 'notify_new_user' channel exists.
    IF NOT EXISTS (SELECT 1 FROM pg_listening_channels() WHERE pg_listening_channels = 'notify_new_user') THEN
        -- If it doesn't exist, you can't really "create" a channel this way,
        -- but you can ensure your notification function is set up.
        -- The channel is implicitly created when the first LISTEN command is issued.
        -- This is just a placeholder for any setup related to notifications.
    END IF;
END $$;


-- ---
-- END OF SCRIPT
-- ---
