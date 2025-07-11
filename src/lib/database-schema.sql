-- InvoChat - v4.0 Final Database Schema
-- This script is designed to be idempotent and can be run multiple times safely.

-- 1. Extensions
-- Enable pgcrypto for gen_random_uuid(), which is more standard than uuid-ossp.
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Custom Types
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

-- 3. Tables
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- The company_id on users table is now managed via raw_app_meta_data,
-- so we do not alter auth.users anymore.

CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold integer NOT NULL DEFAULT 100000,
  fast_moving_days integer NOT NULL DEFAULT 30,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  tax_rate numeric DEFAULT 0,
  custom_rules jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS company_settings_company_id_idx ON public.company_settings(company_id);

CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  barcode text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    deleted_at timestamptz,
    UNIQUE(company_id, name)
);
CREATE INDEX IF NOT EXISTS locations_company_id_idx ON public.locations(company_id);

CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL DEFAULT 0,
  cost integer,
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
  UNIQUE(company_id, product_id, location_id)
);
CREATE INDEX IF NOT EXISTS inventory_product_id_location_id_idx ON public.inventory(product_id, location_id);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);


CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  vendor_name text NOT NULL,
  contact_info text,
  address text,
  terms text,
  account_number text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  deleted_at timestamptz,
  UNIQUE(company_id, vendor_name)
);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);

CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
  po_number text NOT NULL,
  status public.po_status DEFAULT 'draft',
  order_date date NOT NULL,
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
  UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered integer NOT NULL,
  quantity_received integer DEFAULT 0,
  unit_cost integer,
  tax_rate numeric
);
CREATE INDEX IF NOT EXISTS po_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);


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
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);


CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    location_id uuid,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(company_id, product_id, location_id)
);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);


CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
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
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);


CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_number text NOT NULL,
  customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  customer_name text,
  customer_email text,
  total_amount bigint,
  tax_amount bigint,
  payment_method text NOT NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  external_id text,
  UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);

CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity integer NOT NULL,
  unit_price integer NOT NULL,
  cost_at_time integer
);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);


CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  is_starred boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.message_role NOT NULL,
  content text NOT NULL,
  component text,
  component_props jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  is_error boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT true,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);

CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz NOT NULL
);

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
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    product_id uuid NOT NULL,
    location_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_loc_idx ON public.inventory_ledger(product_id, location_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

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
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- 4. Helper Functions & Triggers
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  company_name_text text;
BEGIN
  -- Extract company name from user metadata
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  
  -- Prevent signups without a company name
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id and Owner role
  -- This is the correct, permission-safe way to update user metadata
  PERFORM auth.update_user_by_id(
    new.id,
    jsonb_build_object(
        'app_metadata', new.raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    )
  );

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

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
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();
  
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_integrations_updated_at ON public.integrations;
CREATE TRIGGER trigger_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_channel_fees_updated_at ON public.channel_fees;
CREATE TRIGGER trigger_channel_fees_updated_at BEFORE UPDATE ON public.channel_fees FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();


CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  conversation_company_id uuid;
BEGIN
  SELECT company_id INTO conversation_company_id
  FROM public.conversations
  WHERE id = NEW.conversation_id;

  IF conversation_company_id IS NULL OR conversation_company_id != NEW.company_id THEN
    RAISE EXCEPTION 'Message company_id does not match conversation company_id';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_message_insert_or_update ON public.messages;
CREATE TRIGGER before_message_insert_or_update
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();
  
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id' FROM auth.users WHERE id = auth.uid();
$$;

-- 5. Row Level Security (RLS)
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Company access" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Company access" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.products FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));
CREATE POLICY "User can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "User can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Company access" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Company access" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "User can manage their own export jobs" ON public.export_jobs FOR ALL USING (requested_by_user_id = auth.uid());
CREATE POLICY "Company access" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "User can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Company access" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

-- 6. Grants
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.po_status TO authenticated;

-- Grant access for a future-proof setup
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated, service_role;

-- Special permissions for storage.objects for public access
CREATE POLICY "Enable read access for all users" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-- 7. Advanced RPC Functions
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
  tmp_table_name text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
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
  $fmt$, tmp_table_name);

  -- 2) Populate it from the JSON payload
  EXECUTE format($fmt$
    INSERT INTO %I (product_id, location_id, quantity, unit_price, cost_at_time)
    SELECT
      (item->>'product_id')::uuid,
      (item->>'location_id')::uuid,
      (item->>'quantity')::integer,
      (item->>'unit_price')::integer,
      inv.cost
    FROM jsonb_array_elements($1) AS x(item)
    JOIN public.inventory inv
      ON inv.product_id  = (x.item->>'product_id')::uuid
     AND inv.location_id = (x.item->>'location_id')::uuid
     AND inv.company_id  = $2
  $fmt$, tmp_table_name)
  USING p_sale_items, p_company_id;

  -- 3) Stock checks
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
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
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp_table_name)
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
  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
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


CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name TEXT,
    p_records JSONB,
    p_conflict_columns TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    table_regclass regclass;
BEGIN
    -- Ensure the table exists in the public schema to prevent arbitrary table access
    SELECT to_regclass('public.' || p_table_name) INTO table_regclass;
    IF table_regclass IS NULL THEN
        RAISE EXCEPTION 'Table % not found in public schema.', p_table_name;
    END IF;

    -- Construct the dynamic SQL for upsert
    EXECUTE format(
        'INSERT INTO %s SELECT * FROM jsonb_populate_recordset(null::%s, %L) ON CONFLICT (%s) DO UPDATE SET %s',
        table_regclass,
        table_regclass,
        p_records,
        array_to_string(p_conflict_columns, ', '),
        (SELECT string_agg(column_name || ' = EXCLUDED.' || column_name, ', ')
         FROM information_schema.columns
         WHERE table_name = p_table_name AND table_schema = 'public' AND NOT (column_name = ANY(p_conflict_columns)))
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id UUID,
    p_query TEXT DEFAULT NULL,
    p_category TEXT DEFAULT NULL,
    p_location_id UUID DEFAULT NULL,
    p_supplier_id UUID DEFAULT NULL,
    p_product_id_filter UUID DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    items JSON,
    total_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH inventory_base AS (
        SELECT
            i.product_id,
            p.name as product_name,
            p.sku,
            p.category,
            i.quantity,
            i.cost,
            i.price,
            i.total_value,
            i.on_order_quantity,
            i.landed_cost,
            p.barcode,
            i.location_id,
            l.name as location_name,
            i.version,
            COALESCE(s.monthly_units_sold, 0) as monthly_units_sold,
            COALESCE(s.monthly_profit, 0) as monthly_profit
        FROM public.inventory_view i
        JOIN public.products p ON i.product_id = p.id AND i.company_id = p.company_id
        LEFT JOIN public.locations l ON i.location_id = l.id AND i.company_id = l.company_id
        LEFT JOIN public.product_sales_stats s ON i.product_id = s.product_id AND i.company_id = s.company_id
        WHERE i.company_id = p_company_id
          AND i.deleted_at IS NULL
          AND (p_product_id_filter IS NULL OR i.product_id = p_product_id_filter)
          AND (p_query IS NULL OR p.name ILIKE '%' || p_query || '%' OR p.sku ILIKE '%' || p_query || '%')
          AND (p_category IS NULL OR p.category = p_category)
          AND (p_location_id IS NULL OR i.location_id = p_location_id)
          AND (p_supplier_id IS NULL OR EXISTS (
              SELECT 1 FROM public.supplier_catalogs sc
              WHERE sc.product_id = i.product_id AND sc.supplier_id = p_supplier_id
          ))
    ),
    counted_items AS (
        SELECT *, COUNT(*) OVER() as full_count FROM inventory_base
    )
    SELECT
        json_agg(
            json_build_object(
                'product_id', ci.product_id,
                'product_name', ci.product_name,
                'sku', ci.sku,
                'category', ci.category,
                'quantity', ci.quantity,
                'cost', ci.cost,
                'price', ci.price,
                'total_value', ci.total_value,
                'on_order_quantity', ci.on_order_quantity,
                'landed_cost', ci.landed_cost,
                'barcode', ci.barcode,
                'location_id', ci.location_id,
                'location_name', ci.location_name,
                'version', ci.version,
                'monthly_units_sold', ci.monthly_units_sold,
                'monthly_profit', ci.monthly_profit,
                'reorder_point', rr.min_stock
            )
        ) AS items,
        (SELECT full_count FROM counted_items LIMIT 1) AS total_count
    FROM counted_items ci
    LEFT JOIN public.reorder_rules rr ON ci.product_id = rr.product_id AND ci.location_id = rr.location_id AND rr.company_id = p_company_id
    ORDER BY ci.product_name
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- 8. Views & Materialized Views
CREATE OR REPLACE VIEW public.inventory_view AS
SELECT
    i.id,
    i.company_id,
    i.product_id,
    i.location_id,
    i.quantity,
    i.cost,
    i.price,
    (i.quantity * i.cost) AS total_value,
    i.on_order_quantity,
    i.last_sold_date,
    i.landed_cost,
    i.version,
    i.deleted_at,
    i.deleted_by
FROM public.inventory i
WHERE i.deleted_at IS NULL;

CREATE OR REPLACE VIEW public.product_sales_stats AS
SELECT
    si.company_id,
    si.product_id,
    SUM(si.quantity) as monthly_units_sold,
    SUM(si.quantity * (si.unit_price - si.cost_at_time)) as monthly_profit
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
WHERE s.created_at >= now() - interval '30 days'
GROUP BY si.company_id, si.product_id;

DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    c.id as company_id,
    SUM(i.quantity * i.cost) as inventory_value,
    COUNT(DISTINCT p.id) as total_skus,
    COUNT(DISTINCT CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN p.id ELSE NULL END) as low_stock_count
FROM public.companies c
LEFT JOIN public.products p ON c.id = p.company_id
LEFT JOIN public.inventory i ON p.id = i.product_id
LEFT JOIN public.reorder_rules rr ON p.id = rr.product_id
WHERE p.deleted_at IS NULL
GROUP BY c.id;
CREATE UNIQUE INDEX ON public.company_dashboard_metrics (company_id);


DROP MATERIALIZED VIEW IF EXISTS public.customer_analytics_metrics;
CREATE MATERIALIZED VIEW public.customer_analytics_metrics AS
SELECT
    s.company_id,
    COUNT(DISTINCT s.customer_id) AS total_customers,
    SUM(s.total_amount) AS total_revenue,
    AVG(s.total_amount) AS average_sale_value,
    SUM(CASE WHEN s.created_at >= NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END) AS sales_last_30_days
FROM public.sales s
WHERE s.customer_id IS NOT NULL
GROUP BY s.company_id;
CREATE UNIQUE INDEX ON public.customer_analytics_metrics (company_id);

CREATE OR REPLACE FUNCTION public.refresh_materialized_views()
RETURNS void LANGUAGE sql AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
$$;

-- Initial data population
SELECT public.refresh_materialized_views();
