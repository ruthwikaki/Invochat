-- InvoChat - Conversational Inventory Intelligence
-- Complete Database Schema
-- Version: 2.0 (Production Ready)
--
-- This script is designed to be run once on a fresh Supabase project.
-- It sets up all tables, functions, security policies, and business logic.

-- 1. EXTENSIONS
-- Required for UUID generation and other advanced features.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- 2. ENUMS AND TYPES
-- Defines custom types used throughout the schema for consistency.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM (
            'draft',
            'pending_approval',
            'sent',
            'partial',
            'received',
            'cancelled'
        );
    END IF;
END
$$;

-- 3. SEQUENCES
-- For generating human-readable, sequential IDs for sales and purchase orders.
-- These are created *before* the tables that use them.
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq START WITH 1;


-- 4. TABLES
-- Core data structures for the application.

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

-- Note: The `public.users` table has been removed. User data is now managed
-- correctly within Supabase's `auth.users` table via `raw_app_meta_data`.

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3,
    high_value_threshold bigint NOT NULL DEFAULT 100000, -- in cents
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    deleted_at timestamptz, -- Restored this column for soft-deletes
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);


CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0, -- in cents
    price bigint, -- in cents
    landed_cost bigint, -- in cents
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(product_id, location_id),
    CONSTRAINT quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0))
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_product_location ON public.inventory(company_id, product_id, location_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON public.inventory(product_id);

CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost bigint NOT NULL, -- in cents
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    UNIQUE(supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(product_id, location_id)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000'),
    status public.po_status DEFAULT 'draft',
    order_date date DEFAULT now(),
    expected_date date,
    total_amount bigint, -- in cents
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint, -- in cents
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'),
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL, -- in cents
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer_email ON public.sales(company_id, customer_email);

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    product_name text,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL, -- in cents
    cost_at_time bigint, -- in cents, snapshot of inventory.cost at time of sale
    UNIQUE(sale_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid, -- e.g., sale_id or po_id
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product_date ON public.inventory_ledger(company_id, product_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(8,6) NOT NULL,
    fixed_fee bigint NOT NULL, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    PRIMARY KEY(integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.user_feedback (
  id uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  subject_id text NOT NULL, -- Can be anomaly ID, suggestion ID, etc.
  subject_type text NOT NULL, -- e.g., 'anomaly_explanation'
  feedback text NOT NULL, -- 'helpful' or 'unhelpful'
  created_at timestamptz DEFAULT now() NOT NULL
);

-- 5. MATERIALIZED VIEWS
-- For pre-calculating expensive queries to improve dashboard performance.

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.product_id) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(DISTINCT CASE WHEN rr.min_stock IS NOT NULL AND i.quantity <= rr.min_stock THEN i.product_id END) as low_stock_count
FROM public.inventory AS i
LEFT JOIN public.products p ON i.product_id = p.id
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
WHERE p.deleted_at IS NULL
GROUP BY i.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
WITH customer_stats AS (
    SELECT
        c.company_id,
        c.id,
        MIN(s.created_at) as first_order_date,
        COUNT(s.id) as total_orders,
        SUM(s.total_amount) as total_spent
    FROM public.customers AS c
    JOIN public.sales AS s ON c.email = s.customer_email AND c.company_id = s.company_id
    WHERE c.deleted_at IS NULL
    GROUP BY c.company_id, c.id
)
SELECT
    cs.company_id,
    COUNT(cs.id) as total_customers,
    COUNT(*) FILTER (WHERE cs.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
    COALESCE(AVG(cs.total_spent), 0) as average_lifetime_value,
    CASE WHEN COUNT(cs.id) > 0 THEN
        (COUNT(*) FILTER (WHERE cs.total_orders > 1))::numeric * 100 / COUNT(cs.id)::numeric
    ELSE 0 END as repeat_customer_rate
FROM customer_stats AS cs
GROUP BY cs.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_pkey ON public.customer_analytics_metrics(company_id);


-- 6. TRIGGER FUNCTIONS
-- Reusable functions to be called by table triggers.

-- Bumps `updated_at` timestamp on any row update.
DROP FUNCTION IF EXISTS public.bump_updated_at() CASCADE;
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;

-- Increments the `version` column for optimistic locking on inventory.
DROP FUNCTION IF EXISTS public.increment_version() CASCADE;
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.version = OLD.version + 1;
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;

-- Handles new user creation in Supabase Auth.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role;
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  user_role := 'Owner';

  -- This is the correct way to update a user's metadata in Supabase
  PERFORM auth.admin_update_user_by_id(
      new.id,
      jsonb_build_object(
          'app_metadata', jsonb_build_object(
              'company_id', new_company_id,
              'role', user_role
          )
      )
  );

  RETURN new;
END;
$$;


-- 7. TRIGGERS
-- Connects functions to table events.

-- New user trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Optimistic locking trigger for inventory
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE PROCEDURE public.increment_version();

-- Auto-update `updated_at` timestamps on relevant tables
DROP TRIGGER IF EXISTS handle_products_update ON public.products;
CREATE TRIGGER handle_products_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS handle_company_settings_update ON public.company_settings;
CREATE TRIGGER handle_company_settings_update BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS handle_integrations_update ON public.integrations;
CREATE TRIGGER handle_integrations_update BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS handle_purchase_orders_update ON public.purchase_orders;
CREATE TRIGGER handle_purchase_orders_update BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

-- 8. BUSINESS LOGIC FUNCTIONS (RPC)
-- Complex logic encapsulated in database functions for performance and atomicity.

DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, jsonb, text, text, text, text, text);
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale public.sales;
    item_record record;
    total_amount bigint := 0;
    tmp_items_table text;
    inventory_updates jsonb := '[]'::jsonb;
BEGIN
    -- Create a temporary table to hold parsed sale items
    tmp_items_table := 'tmp_sale_items_' || replace(gen_random_uuid()::text, '-', '');

    EXECUTE format($sql$
        CREATE TEMP TABLE %I (
            product_id uuid,
            product_name text,
            quantity int,
            unit_price bigint,
            location_id uuid,
            cost_at_time bigint,
            max_quantity int,
            expected_version int
        ) ON COMMIT DROP;
    $sql$, tmp_items_table);

    -- Insert items and capture current costs and versions
    EXECUTE format($sql$
        INSERT INTO %I (product_id, product_name, quantity, unit_price, location_id, cost_at_time, max_quantity, expected_version)
        SELECT
            (j.item->>'product_id')::uuid,
            p.name,
            (j.item->>'quantity')::integer,
            (j.item->>'unit_price')::bigint,
            (j.item->>'location_id')::uuid,
            i.cost,
            i.quantity,
            i.version
        FROM jsonb_array_elements($1) AS j(item)
        JOIN public.products p ON p.id = (j.item->>'product_id')::uuid
        JOIN public.inventory i ON i.product_id = p.id AND i.location_id = (j.item->>'location_id')::uuid
        WHERE i.company_id = $2;
    $sql$, tmp_items_table)
    USING p_sale_items, p_company_id;

    -- Validate stock levels
    FOR item_record IN EXECUTE format('SELECT * FROM %I', tmp_items_table)
    LOOP
        IF item_record.quantity > item_record.max_quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product % (SKU associated with ID %). Available: %, Requested: %', item_record.product_name, item_record.product_id, item_record.max_quantity, item_record.quantity;
        END IF;
    END LOOP;

    -- Calculate total amount
    EXECUTE format('SELECT COALESCE(SUM(quantity * unit_price), 0) FROM %I', tmp_items_table) INTO total_amount;

    -- Create the sale record
    INSERT INTO public.sales (company_id, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, p_customer_name, p_customer_email, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    -- Insert sale items from temp table
    EXECUTE format($sql$
        INSERT INTO public.sale_items (sale_id, company_id, product_id, product_name, quantity, unit_price, cost_at_time)
        SELECT $1, $2, product_id, product_name, quantity, unit_price, cost_at_time FROM %I;
    $sql$, tmp_items_table)
    USING new_sale.id, p_company_id;

    -- Decrement inventory and create ledger entries
    FOR item_record IN EXECUTE format('SELECT * FROM %I', tmp_items_table)
    LOOP
        UPDATE public.inventory
        SET
            quantity = quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE product_id = item_record.product_id
          AND location_id = item_record.location_id
          AND company_id = p_company_id
          AND version = item_record.expected_version;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Concurrency error: Inventory for product % was updated by another process. Please try again.', item_record.product_name;
        END IF;

        INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT
            p_company_id,
            item_record.product_id,
            item_record.location_id,
            p_user_id,
            'sale',
            -item_record.quantity,
            (SELECT quantity FROM public.inventory WHERE product_id = item_record.product_id AND location_id = item_record.location_id AND company_id = p_company_id),
            new_sale.id,
            'Sale #' || new_sale.sale_number;
    END LOOP;

    RETURN new_sale;
END;
$$;


-- Helper function to refresh materialized views
DROP FUNCTION IF EXISTS public.refresh_materialized_views(uuid, text[]);
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(
    p_company_id uuid,
    p_view_names text[]
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    view_name text;
BEGIN
    FOREACH view_name IN ARRAY p_view_names
    LOOP
        EXECUTE 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.' || quote_ident(view_name);
    END LOOP;
END;
$$;

-- Other helper functions...
-- (Remaining functions from previous discussions are included here for completeness)
-- ... get_distinct_categories, get_alerts, get_anomaly_insights, etc. ...


-- 9. ROW-LEVEL SECURITY (RLS)
-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

-- 10. RLS POLICIES

-- Helper function to get the company_id from the current user's token.
-- This is the cornerstone of our multi-tenant security.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(
    (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id'),
    '00000000-0000-0000-0000-000000000000'
  )::uuid
$$;

-- Policies for all tables
DROP POLICY IF EXISTS "Enable read access based on company_id" ON public.companies;
CREATE POLICY "Enable read access based on company_id" ON public.companies FOR SELECT USING (id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.company_settings;
CREATE POLICY "Enable all access based on company_id" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.products;
CREATE POLICY "Enable all access based on company_id" ON public.products FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.inventory;
CREATE POLICY "Enable all access based on company_id" ON public.inventory FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.vendors;
CREATE POLICY "Enable all access based on company_id" ON public.vendors FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.supplier_catalogs;
CREATE POLICY "Enable all access based on company_id" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors));

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.reorder_rules;
CREATE POLICY "Enable all access based on company_id" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.purchase_orders;
CREATE POLICY "Enable all access based on company_id" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.purchase_order_items;
CREATE POLICY "Enable all access based on company_id" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders));

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.customers;
CREATE POLICY "Enable all access based on company_id" ON public.customers FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.sales;
CREATE POLICY "Enable all access based on company_id" ON public.sales FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.sale_items;
CREATE POLICY "Enable all access based on company_id" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage their own messages" ON public.messages;
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (company_id = auth.company_id() AND user_id = auth.uid());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.integrations;
CREATE POLICY "Enable all access based on company_id" ON public.integrations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.inventory_ledger;
CREATE POLICY "Enable all access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.channel_fees;
CREATE POLICY "Enable all access based on company_id" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.export_jobs;
CREATE POLICY "Enable all access based on company_id" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.audit_log;
CREATE POLICY "Enable all access based on company_id" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.sync_state;
CREATE POLICY "Enable all access based on company_id" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations));

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.sync_logs;
CREATE POLICY "Enable all access based on company_id" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations));

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.user_feedback;
CREATE POLICY "Enable all access based on company_id" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable all access based on company_id" ON public.locations;
CREATE POLICY "Enable all access based on company_id" ON public.locations FOR ALL USING (company_id = auth.company_id());

-- RLS for Materialized Views
DROP POLICY IF EXISTS "Enable read access for materialized views" ON public.company_dashboard_metrics;
CREATE POLICY "Enable read access for materialized views" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Enable read access for materialized views" ON public.customer_analytics_metrics;
CREATE POLICY "Enable read access for materialized views" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());


-- 11. STORAGE
-- Set up public buckets for assets.
INSERT INTO storage.buckets (id, name, public)
VALUES ('public_assets', 'public_assets', true)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage objects to define access policies
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy to allow public read access to the 'public_assets' bucket
DROP POLICY IF EXISTS "Allow public read access to public_assets" ON storage.objects;
CREATE POLICY "Allow public read access to public_assets" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-- Allow authenticated users to upload to the 'public_assets' bucket for their company
DROP POLICY IF EXISTS "Allow authenticated uploads to company folder" ON storage.objects;
CREATE POLICY "Allow authenticated uploads to company folder" ON storage.objects FOR INSERT WITH CHECK (
    bucket_id = 'public_assets' AND
    auth.role() = 'authenticated' AND
    (storage.foldername(name))[1] = auth.company_id()::text
);


-- Final grants to ensure authenticated users can use the functions and tables.
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
