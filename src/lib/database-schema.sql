
-- =============================================
-- INVOCHAT DATABASE SCHEMA
-- Version: 4.2
-- =============================================
-- This script is idempotent and can be run multiple times safely.
-- It is designed to be run in the Supabase SQL Editor.

-- 1. EXTENSIONS
-- =============================================
-- Enable pgcrypto for gen_random_uuid(), which is standard and secure.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENUMS
-- =============================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
    CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled', 'pending_approval');
  END IF;
   IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
    CREATE TYPE public.message_role AS ENUM ('user', 'assistant');
  END IF;
END
$$;

-- 3. TABLES
-- =============================================
-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- Users Table (extends auth.users)
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  role public.user_role NOT NULL DEFAULT 'Member',
  deleted_at timestamptz
);
-- Add role to user app_metadata for easy access in RLS policies
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS role public.user_role;

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  fast_moving_days integer NOT NULL DEFAULT 30,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold integer NOT NULL DEFAULT 100000,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text NOT NULL DEFAULT 'USD',
  timezone text NOT NULL DEFAULT 'UTC',
  tax_rate numeric NOT NULL DEFAULT 0.0,
  custom_rules jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  barcode text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE (company_id, sku)
);

-- Locations Table
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean NOT NULL DEFAULT false,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, name)
);

-- Inventory Table
CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL DEFAULT 0,
  cost integer NOT NULL DEFAULT 0,
  price integer,
  landed_cost integer,
  on_order_quantity integer NOT NULL DEFAULT 0,
  last_sold_date date,
  version integer NOT NULL DEFAULT 1,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES auth.users(id),
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id),
  CHECK (quantity >= 0)
);

-- Reorder Rules Table
CREATE TABLE IF NOT EXISTS public.reorder_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
  rule_type text DEFAULT 'manual',
  min_stock integer,
  max_stock integer,
  reorder_quantity integer,
  UNIQUE (company_id, product_id, location_id),
  CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock),
  CHECK (reorder_quantity IS NULL OR reorder_quantity > 0)
);

-- Vendors (Suppliers) Table
CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  vendor_name text NOT NULL,
  contact_info text,
  address text,
  terms text,
  account_number text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE (company_id, vendor_name)
);

-- Supplier Catalogs Table
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  supplier_sku text,
  unit_cost integer NOT NULL,
  moq integer DEFAULT 1,
  lead_time_days integer,
  is_active boolean DEFAULT true,
  UNIQUE(supplier_id, product_id)
);

-- Purchase Orders Sequence
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE RESTRICT,
  po_number text NOT NULL,
  status public.po_status DEFAULT 'draft',
  order_date date NOT NULL DEFAULT CURRENT_DATE,
  expected_date date,
  total_amount bigint,
  tax_amount bigint,
  shipping_cost bigint,
  notes text,
  requires_approval boolean DEFAULT false,
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE (company_id, po_number)
);

ALTER TABLE public.purchase_orders
  ALTER COLUMN po_number
  SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


-- Purchase Order Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered integer NOT NULL,
  quantity_received integer NOT NULL DEFAULT 0,
  unit_cost integer NOT NULL,
  tax_rate numeric
);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, email)
);

-- Sales Sequence
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_number text NOT NULL,
  customer_id uuid REFERENCES public.customers(id),
  customer_name text,
  customer_email text,
  total_amount bigint NOT NULL,
  tax_amount bigint,
  payment_method text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  external_id text
);


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
  quantity integer NOT NULL,
  unit_price integer NOT NULL,
  cost_at_time integer NOT NULL
);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  is_starred boolean NOT NULL DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.message_role NOT NULL,
  content text NOT NULL,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  component text,
  component_props jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL DEFAULT 0,
    fixed_fee integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean NOT NULL DEFAULT true,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

-- Sync State Table
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    UNIQUE(integration_id, sync_type)
);

-- Sync Logs Table
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    status text NOT NULL,
    records_synced integer,
    error_message text,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- User Feedback Table
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamptz NOT NULL DEFAULT now()
);


-- 4. INDEXES
-- =============================================
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_company_product_location_idx ON public.inventory(company_id, product_id, location_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS po_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS po_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_location_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);


-- 5. HELPER FUNCTIONS
-- =============================================
-- Helper to get company_id from a user's JWT claims.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'::text;
$$;


-- 6. TRIGGERS & TRIGGER FUNCTIONS
-- =============================================

-- Generic function to bump updated_at timestamp
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Generic function to increment version number and bump updated_at
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

-- Trigger to create a new user profile upon signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty during signup.';
  END IF;

  INSERT INTO public.companies (name) VALUES (company_name_text) RETURNING id INTO new_company_id;
  INSERT INTO public.users (id, company_id, role) VALUES (new.id, new_company_id, 'Owner');
  UPDATE auth.users SET app_metadata = jsonb_set(new.raw_user_meta_data, '{company_id}', to_jsonb(new_company_id), true) || jsonb_build_object('role', 'Owner') WHERE id = new.id;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Trigger to apply the version increment on inventory updates
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();


-- Add bump_updated_at triggers to all relevant tables
DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at
  BEFORE UPDATE ON public.locations
  FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at
  BEFORE UPDATE ON public.vendors
  FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at
  BEFORE UPDATE ON public.purchase_orders
  FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_company_settings_updated_at ON public.company_settings;
CREATE TRIGGER trigger_company_settings_updated_at
  BEFORE UPDATE ON public.company_settings
  FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

-- Trigger to ensure message.company_id matches conversation.company_id
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  conv_company_id uuid;
BEGIN
  SELECT company_id INTO conv_company_id FROM public.conversations WHERE id = NEW.conversation_id;
  IF NEW.company_id IS DISTINCT FROM conv_company_id THEN
    RAISE EXCEPTION 'Message company_id does not match conversation company_id';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enforce_message_company_id ON public.messages;
CREATE TRIGGER trigger_enforce_message_company_id
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();


-- 7. RPC FUNCTIONS
-- =============================================

-- RPC to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
  p_company_id   uuid,
  p_user_id      uuid,
  p_sale_items   jsonb,
  p_customer_name text     DEFAULT NULL,
  p_customer_email text    DEFAULT NULL,
  p_payment_method text    DEFAULT 'other',
  p_notes         text     DEFAULT NULL,
  p_external_id   text     DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
  new_sale       public.sales;
  new_customer   uuid;
  total_amount   bigint;
  tax_rate       numeric;
  tax_amount     numeric;
  item_rec       record;
  tmp            text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  -- 1) Create the temp table
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP
  $fmt$, tmp);

  -- 2) Populate it from the JSON payload, joining to get cost
  EXECUTE format($fmt$
    INSERT INTO %I (product_id, location_id, quantity, unit_price, cost_at_time)
    SELECT
      (item->>'product_id')::uuid,
      (item->>'location_id')::uuid,
      (item->>'quantity')::int,
      (item->>'unit_price')::int,
      inv.cost
    FROM jsonb_array_elements($1) AS x(item)
    JOIN public.inventory inv
      ON inv.product_id  = (x.item->>'product_id')::uuid
     AND inv.location_id = (x.item->>'location_id')::uuid
     AND inv.company_id  = $2
  $fmt$, tmp)
  USING p_sale_items, p_company_id;

  -- 3) Stock checks
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory
      WHERE company_id  = p_company_id
        AND product_id  = item_rec.product_id
        AND location_id = item_rec.location_id
        AND quantity    >= item_rec.quantity
    ) THEN
      RAISE EXCEPTION 'Insufficient stock for product % at location %',
        item_rec.product_id, item_rec.location_id;
    END IF;
  END LOOP;

  -- 4) Totals & tax
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp)
  INTO total_amount;

  SELECT cs.tax_rate INTO tax_rate
    FROM public.company_settings cs
   WHERE cs.company_id = p_company_id;
  tax_amount := total_amount * COALESCE(tax_rate,0);

  -- 5) Upsert customer
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id,email)
    DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer;
  END IF;

  -- 6) Insert sale header
  INSERT INTO public.sales (
    company_id, sale_number, customer_id,
    customer_name, customer_email,
    total_amount, tax_amount,
    payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id,
    'SALE-'||TO_CHAR(nextval('sales_sale_number_seq'),'FM000000'),
    new_customer,
    p_customer_name, p_customer_email,
    total_amount, tax_amount,
    p_payment_method, p_notes,
    p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  -- 7) Items + ledger + inventory update
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp)
  LOOP
    INSERT INTO public.sale_items (
      sale_id, company_id, product_id,
      location_id, quantity, unit_price, cost_at_time
    )
    VALUES (
      new_sale.id, p_company_id, item_rec.product_id,
      item_rec.location_id, item_rec.quantity,
      item_rec.unit_price, item_rec.cost_at_time
    );

    UPDATE public.inventory
    SET
      quantity      = quantity - item_rec.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id  = p_company_id
      AND product_id  = item_rec.product_id
      AND location_id = item_rec.location_id;

    INSERT INTO public.inventory_ledger(
      company_id, product_id, location_id,
      change_type, quantity_change, new_quantity,
      related_id, notes, created_by
    )
    VALUES (
      p_company_id, item_rec.product_id, item_rec.location_id,
      'sale', -item_rec.quantity,
      (SELECT quantity FROM public.inventory
         WHERE product_id=item_rec.product_id
           AND location_id=item_rec.location_id
           AND company_id=p_company_id),
      new_sale.id,
      'Sale #'||new_sale.sale_number,
      p_user_id
    );
  END LOOP;

  RETURN new_sale;
END;
$$;


-- RPC to transfer inventory between locations
CREATE OR REPLACE FUNCTION public.transfer_inventory(
    p_company_id uuid,
    p_product_id uuid,
    p_from_location_id uuid,
    p_to_location_id uuid,
    p_quantity integer,
    p_notes text,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    current_from_quantity integer;
    current_to_quantity integer;
BEGIN
    -- Lock rows to prevent race conditions
    SELECT quantity INTO current_from_quantity FROM public.inventory
    WHERE company_id = p_company_id AND product_id = p_product_id AND location_id = p_from_location_id FOR UPDATE;

    IF current_from_quantity IS NULL OR current_from_quantity < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock at source location';
    END IF;

    -- Decrement from source
    UPDATE public.inventory SET quantity = quantity - p_quantity
    WHERE company_id = p_company_id AND product_id = p_product_id AND location_id = p_from_location_id;

    -- Log decrement
    INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, notes, created_by)
    VALUES (p_company_id, p_product_id, p_from_location_id, 'transfer_out', -p_quantity, current_from_quantity - p_quantity, p_notes, p_user_id);

    -- Increment at destination
    UPDATE public.inventory SET quantity = quantity + p_quantity
    WHERE company_id = p_company_id AND product_id = p_product_id AND location_id = p_to_location_id
    RETURNING quantity INTO current_to_quantity;
    
    -- If destination row doesn't exist, create it
    IF NOT FOUND THEN
        INSERT INTO public.inventory(company_id, product_id, location_id, quantity, cost, price)
        SELECT p_company_id, p_product_id, p_to_location_id, p_quantity, i.cost, i.price
        FROM public.inventory i WHERE i.company_id = p_company_id AND i.product_id = p_product_id AND i.location_id = p_from_location_id;
        current_to_quantity := p_quantity;
    END IF;

    -- Log increment
    INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, notes, created_by)
    VALUES (p_company_id, p_product_id, p_to_location_id, 'transfer_in', p_quantity, current_to_quantity, p_notes, p_user_id);
END;
$$;

-- RPC for batch upserting
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
  p_table_name text,
  p_records jsonb,
  p_conflict_columns text[]
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  conflict_clause text;
  update_clause text;
  query text;
BEGIN
  -- Ensure table is in 'public' schema for security
  IF NOT EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = p_table_name
  ) THEN
      RAISE EXCEPTION 'Table must be in the public schema';
  END IF;

  conflict_clause := 'ON CONFLICT (' || array_to_string(p_conflict_columns, ', ') || ') DO UPDATE SET ';
  
  SELECT string_agg(
      format('%I = EXCLUDED.%I', col.column_name, col.column_name),
      ', '
  )
  INTO update_clause
  FROM information_schema.columns col
  WHERE col.table_schema = 'public' AND col.table_name = p_table_name
    AND col.column_name <> ALL(p_conflict_columns);

  query := format(
    'INSERT INTO public.%I SELECT * FROM jsonb_populate_recordset(null::public.%I, %L) %s %s;',
    p_table_name,
    p_table_name,
    p_records,
    conflict_clause,
    update_clause
  );
  
  EXECUTE query;
END;
$$;

-- 8. MATERIALIZED VIEWS
-- =============================================

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  c.id as company_id,
  SUM(i.quantity * i.cost) AS inventory_value,
  COUNT(DISTINCT i.product_id) AS total_skus,
  COUNT(DISTINCT CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN i.product_id END) AS low_stock_count
FROM public.companies c
LEFT JOIN public.inventory i ON c.id = i.company_id AND i.deleted_at IS NULL
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
GROUP BY c.id;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
    s.company_id,
    c.id as customer_id,
    c.customer_name,
    c.email,
    COUNT(s.id) as total_orders,
    SUM(s.total_amount) as total_spent
FROM public.sales s
JOIN public.customers c ON s.customer_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY s.company_id, c.id, c.customer_name, c.email;


-- 9. PERMISSIONS & RLS
-- =============================================

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT USAGE ON SCHEMA storage TO authenticated, service_role;

-- Grant usage on enums
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.po_status TO authenticated;
GRANT USAGE ON TYPE public.message_role TO authenticated;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Set up RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

-- Define Policies
CREATE POLICY "Company access for all tables" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Users can manage their own user record" ON public.users FOR ALL USING (id = auth.uid());
CREATE POLICY "Company access to settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access to products" ON public.products FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to PO items" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access to sales" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Company access to inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to sync state" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to sync logs" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Company access to dashboard metrics" ON public.company_dashboard_metrics FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access to customer metrics" ON public.customer_analytics_metrics FOR ALL USING (company_id = auth.company_id());

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO authenticated;

-- STORAGE POLICIES
-- Create a policy to allow public read access to the 'public_assets' bucket
CREATE POLICY "Enable read access for all users" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-- 10. FINAL SETUP
-- =============================================
-- Function to refresh all materialized views
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(
    p_company_id uuid,
    p_view_names text[] DEFAULT ARRAY['company_dashboard_metrics', 'customer_analytics_metrics']
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF 'company_dashboard_metrics' = ANY(p_view_names) THEN
        REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
    END IF;
    IF 'customer_analytics_metrics' = ANY(p_view_names) THEN
        REFRESH MATERIALIZED VIEW public.customer_analytics_metrics;
    END IF;
END;
$$;

-- Initial refresh of materialized views
-- Note: This will only work if there is at least one company in the system.
-- It's safe to run as it won't error if there's no data.
-- SELECT public.refresh_materialized_views(auth.company_id());

-- Grant execute on all functions to authenticated users
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;

-- Done!
SELECT 'Database setup complete.';
