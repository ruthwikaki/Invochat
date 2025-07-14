-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: This script sets up the entire database schema for InvoChat,
-- including tables, views, functions, and row-level security policies.
-- It is designed to be idempotent and can be run multiple times safely.

--
-- ==== Extensions ====
--
-- Enable the pgcrypto extension for generating UUIDs.
create extension if not exists "pgcrypto" with schema "extensions";
-- Enable the vault extension for secrets management.
create extension if not exists "supabase_vault" with schema "vault";

--
-- ==== Helper Functions ====
--
-- Function to get the current user's company ID from their JWT claims.
-- This is central to our multi-tenant security model.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;

-- Function to get the current user's role from their JWT claims.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::json->>'user_role', '');
$$;

-- Trigger function to automatically update the `updated_at` timestamp on row modification.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now() at time zone 'utc';
    RETURN NEW;
END;
$$;

--
-- ==== Tables ====
--
-- Companies: Represents a tenant in the application.
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);

-- Company Settings: Tenant-specific business logic parameters.
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days int DEFAULT 90 NOT NULL,
  fast_moving_days int DEFAULT 30 NOT NULL,
  overstock_multiplier numeric DEFAULT 3.0 NOT NULL,
  high_value_threshold int DEFAULT 100000 NOT NULL,
  predictive_stock_days int DEFAULT 7 NOT NULL,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz
);

-- Products: Core product catalog information.
CREATE TABLE IF NOT EXISTS public.products (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  handle text,
  product_type text,
  tags text[],
  status text,
  image_url text,
  external_product_id text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, external_product_id)
);

-- Product Variants: Specific versions of a product (e.g., by size or color).
CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text,
  title text,
  option1_name text,
  option1_value text,
  option2_name text,
  option2_value text,
  option3_name text,
  option3_value text,
  barcode text,
  price int,
  compare_at_price int,
  cost int,
  inventory_quantity int DEFAULT 0 NOT NULL,
  external_variant_id text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, sku),
  UNIQUE(company_id, external_variant_id)
);

-- Locations: Warehouses or other places where inventory is stored.
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
    updated_at timestamptz
);

-- Customers: Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  customer_name text,
  email text,
  total_orders int DEFAULT 0 NOT NULL,
  total_spent int DEFAULT 0 NOT NULL,
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz
);

-- Orders: Records of sales transactions.
CREATE TABLE IF NOT EXISTS public.orders (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  order_number text,
  external_order_id text,
  customer_id uuid REFERENCES public.customers(id),
  financial_status text,
  fulfillment_status text,
  currency text,
  subtotal int NOT NULL,
  total_tax int,
  total_shipping int,
  total_discounts int,
  total_amount int NOT NULL,
  source_platform text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz
);

-- Order Line Items: Individual items within an order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  variant_id uuid REFERENCES public.product_variants(id),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_name text,
  variant_title text,
  sku text,
  quantity int NOT NULL,
  price int NOT NULL,
  total_discount int,
  tax_amount int,
  cost_at_time int,
  external_line_item_id text
);

-- Suppliers: Vendor information.
CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days int,
  notes text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz
);

-- Conversations: Stores chat history.
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  last_accessed_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  is_starred boolean DEFAULT false NOT NULL
);

-- Messages: Individual messages within a conversation.
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id),
  role text NOT NULL,
  content text NOT NULL,
  visualization jsonb,
  confidence real,
  assumptions text[],
  component text,
  componentProps jsonb,
  isError boolean,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);

-- Integrations: Stores credentials and settings for connected platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT true NOT NULL,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

-- Inventory Ledger: An immutable log of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
  quantity_change int NOT NULL,
  new_quantity int NOT NULL,
  related_id uuid, -- e.g., order_id, purchase_order_id
  notes text,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);

-- Audit Log: Records significant user actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL
);

-- Webhook Events: Logs incoming webhook IDs to prevent replay attacks.
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  webhook_id text NOT NULL,
  created_at timestamptz DEFAULT (now() at time zone 'utc') NOT NULL,
  UNIQUE(integration_id, webhook_id)
);


--
-- ==== Views ====
--
-- A denormalized view to simplify querying product and variant data together.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
  pv.id,
  pv.product_id,
  pv.company_id,
  pv.sku,
  pv.title,
  pv.price,
  pv.cost,
  pv.inventory_quantity,
  pv.created_at,
  pv.updated_at,
  p.title AS product_title,
  p.status AS product_status,
  p.product_type,
  p.image_url,
  l.name as location_name,
  l.id as location_id
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id
LEFT JOIN public.locations l ON pv.location_id = l.id;

--
-- ==== Indexes ====
--
-- Create indexes on frequently queried columns to improve performance.
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id_action ON public.audit_log(company_id, action);
CREATE INDEX IF NOT EXISTS idx_products_tags ON public.products USING GIN (tags);

--
-- ==== Auth & User Management ====
--
-- This function runs once upon user creation to set up their company and role.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, defaulting if not present
  v_company_name := new.raw_user_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := new.email;
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Update the user's app_metadata with the new company_id and their role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object(
      'company_id', v_company_id,
      'role', 'Owner'
    )
  where id = new.id;

  RETURN new;
END;
$$;

-- Trigger to execute the handle_new_user function after a new user is created.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

--
-- ==== Triggers for `updated_at` timestamps ====
--
-- Helper function to apply the `set_updated_at` trigger to a given table.
CREATE OR REPLACE FUNCTION public.apply_updated_at_trigger(table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('
        DROP TRIGGER IF EXISTS handle_updated_at ON public.%I;
        CREATE TRIGGER handle_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.set_updated_at();
    ', table_name, table_name);
END;
$$;

-- Apply the trigger to all tables that have an `updated_at` column.
SELECT public.apply_updated_at_trigger(table_name)
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN (
    'company_settings', 'products', 'product_variants', 'customers',
    'orders', 'suppliers', 'integrations'
);


--
-- ==== Row-Level Security (RLS) ====
--
-- Enable RLS for all relevant tables.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;


-- Helper function to create a standard RLS policy for a table.
CREATE OR REPLACE FUNCTION public.create_company_rls_policy(p_table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('
        DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.%I;
        CREATE POLICY "Allow full access based on company_id"
        ON public.%I
        FOR ALL
        USING (company_id = get_current_company_id())
        WITH CHECK (company_id = get_current_company_id());
    ', p_table_name, p_table_name);
END;
$$;

-- Apply the standard RLS policy to all tables with a `company_id` column.
SELECT public.create_company_rls_policy(table_name)
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'company_id';


-- Special RLS policies for tables without a direct `company_id` or with unique requirements.
DROP POLICY IF EXISTS "Users can only see their own company." ON public.companies;
CREATE POLICY "Users can only see their own company."
ON public.companies FOR SELECT
USING (id = get_current_company_id());

DROP POLICY IF EXISTS "Users can see other users in their own company." ON auth.users;
CREATE POLICY "Users can see other users in their own company."
ON auth.users FOR SELECT
USING ((raw_app_meta_data->>'company_id')::uuid = get_current_company_id());

DROP POLICY IF EXISTS "Allow full access to own conversations" ON public.conversations;
CREATE POLICY "Allow full access to own conversations"
ON public.conversations FOR ALL
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Allow full access to messages in own conversations" ON public.messages;
CREATE POLICY "Allow full access to messages in own conversations"
ON public.messages FOR ALL
USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Allow read access to company audit log" ON public.audit_log;
CREATE POLICY "Allow read access to company audit log"
ON public.audit_log FOR SELECT
USING (company_id = get_current_company_id());

DROP POLICY IF EXISTS "Allow read access to webhook_events" ON public.webhook_events;
CREATE POLICY "Allow read access to webhook_events"
ON public.webhook_events FOR SELECT
USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = get_current_company_id()));


--
-- ==== Stored Procedures & Advanced Functions ====
--

-- Function to record a sale from an integrated platform.
-- This function is idempotent based on the platform and external order ID.
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_line_item jsonb;
    v_variant record;
BEGIN
    -- This function now centralizes the logic for handling order data from any platform.
    -- The specific transformations for each platform are handled within the CASE statement.

    -- Upsert customer and get their ID
    INSERT INTO public.customers (company_id, email, customer_name)
    SELECT
        p_company_id,
        payload->>'email',
        payload->>'name'
    FROM (
        SELECT
            CASE p_platform
                WHEN 'shopify' THEN jsonb_build_object('email', p_order_payload->'customer'->>'email', 'name', p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name')
                WHEN 'woocommerce' THEN jsonb_build_object('email', p_order_payload->'billing'->>'email', 'name', p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name')
                ELSE jsonb_build_object('email', 'unknown@example.com', 'name', 'Unknown Customer')
            END AS payload
    ) AS customer_data
    ON CONFLICT (company_id, email) DO UPDATE
    SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Upsert the order
    INSERT INTO public.orders (
        company_id, external_order_id, customer_id, financial_status, fulfillment_status,
        currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
    )
    SELECT
        p_company_id,
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    ON CONFLICT (company_id, source_platform, external_order_id) DO NOTHING
    RETURNING id INTO v_order_id;
    
    -- If the order already existed, v_order_id will be NULL. We should exit.
    IF v_order_id IS NULL THEN
        RETURN;
    END IF;

    -- Loop through line items and record them
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding variant in our database
        SELECT * INTO v_variant
        FROM public.product_variants pv
        WHERE pv.company_id = p_company_id
          AND (pv.external_variant_id = v_line_item->>'variant_id' OR pv.sku = v_line_item->>'sku')
        LIMIT 1;

        IF v_variant IS NOT NULL THEN
            -- Use SELECT ... FOR UPDATE to lock the variant row during the transaction
            -- This prevents race conditions where two orders might try to claim the last item.
            SELECT * INTO v_variant FROM public.product_variants WHERE id = v_variant.id FOR UPDATE;

            -- Insert the line item
            INSERT INTO public.order_line_items (
                order_id, variant_id, company_id, product_name, variant_title, sku,
                quantity, price, total_discount, cost_at_time, external_line_item_id
            )
            VALUES (
                v_order_id, v_variant.id, p_company_id, v_line_item->>'name', v_line_item->>'title', v_line_item->>'sku',
                (v_line_item->>'quantity')::int, (v_line_item->>'price')::numeric * 100,
                (v_line_item->>'total_discount')::numeric * 100, v_variant.cost, v_line_item->>'id'
            );

            -- Update inventory quantity and log the change
            UPDATE public.product_variants
            SET inventory_quantity = inventory_quantity - (v_line_item->>'quantity')::int
            WHERE id = v_variant.id;
            
            INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
            VALUES (p_company_id, v_variant.id, 'sale', -(v_line_item->>'quantity')::int, v_variant.inventory_quantity - (v_line_item->>'quantity')::int, v_order_id);
        END IF;
    END LOOP;
END;
$$;


-- Function to get reorder suggestions
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE (
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_name text,
    supplier_id uuid,
    current_quantity integer,
    suggested_reorder_quantity integer,
    unit_cost integer
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- This is a simplified reorder logic. A real-world scenario would be much more complex,
    -- likely involving sales velocity, lead times, safety stock, etc.
    RETURN QUERY
    SELECT
        pv.id AS variant_id,
        pv.product_id,
        pv.sku,
        p.title AS product_name,
        s.name AS supplier_name,
        s.id AS supplier_id,
        pv.inventory_quantity AS current_quantity,
        (pv.reorder_quantity - pv.inventory_quantity) AS suggested_reorder_quantity,
        pv.cost AS unit_cost
    FROM public.product_variants pv
    JOIN public.products p ON pv.product_id = p.id
    LEFT JOIN public.suppliers s ON p.supplier_id = s.id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity < pv.reorder_point
      AND pv.reorder_point IS NOT NULL
      AND pv.reorder_quantity IS NOT NULL;
END;
$$;


-- Function to get a dead stock report
CREATE OR REPLACE FUNCTION public.get_dead_stock_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date date
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_dead_stock_days int;
BEGIN
    SELECT cs.dead_stock_days INTO v_dead_stock_days
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    RETURN QUERY
    WITH last_sale AS (
        SELECT
            oli.variant_id,
            MAX(o.created_at)::date AS last_sold
        FROM public.order_line_items oli
        JOIN public.orders o ON oli.order_id = o.id
        WHERE o.company_id = p_company_id
        GROUP BY oli.variant_id
    )
    SELECT
        pv.sku,
        p.title AS product_name,
        pv.inventory_quantity AS quantity,
        (pv.inventory_quantity * (pv.cost / 100.0)) AS total_value,
        ls.last_sold AS last_sale_date
    FROM public.product_variants pv
    JOIN public.products p ON pv.product_id = p.id
    LEFT JOIN last_sale ls ON pv.id = ls.variant_id
    WHERE pv.company_id = p_company_id
      AND pv.inventory_quantity > 0
      AND (ls.last_sold IS NULL OR ls.last_sold < (now() - (v_dead_stock_days || ' days')::interval));
END;
$$;

-- Function to clean up old, irrelevant data to keep the database performant.
-- This is intended to be run by a cron job.
CREATE OR REPLACE FUNCTION public.cleanup_old_data()
RETURNS void AS $$
DECLARE
  retention_period_audit interval := '90 days';
  retention_period_messages interval := '180 days';
BEGIN
  -- Delete old audit logs
  DELETE FROM public.audit_log
  WHERE created_at < (now() - retention_period_audit);

  -- Delete old messages from unstarred conversations
  DELETE FROM public.messages
  WHERE conversation_id IN (
    SELECT id FROM public.conversations
    WHERE is_starred = false AND last_accessed_at < (now() - retention_period_messages)
  );

  -- Optionally, delete old unstarred conversations themselves
  DELETE FROM public.conversations
  WHERE is_starred = false AND last_accessed_at < (now() - retention_period_messages);
END;
$$ LANGUAGE plpgsql;

-- Final script execution confirmation
SELECT 'Database schema setup complete.';

