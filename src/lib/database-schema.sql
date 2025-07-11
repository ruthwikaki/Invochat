
-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant usage on the schema to the supabase_auth_admin role
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;

-- Grant usage on the schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;

-- Define custom types for use in tables
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

GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.po_status TO authenticated;
GRANT USAGE ON TYPE public.message_role TO authenticated;


-- =============================================
--                 TABLES
-- =============================================
CREATE TABLE public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.user_role NOT NULL DEFAULT 'Member',
  deleted_at timestamptz,
  -- Mirror other auth.users fields if needed for joins
  email text UNIQUE
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);

CREATE TABLE public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days int NOT NULL DEFAULT 90,
  overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3.0,
  high_value_threshold int NOT NULL DEFAULT 100000,
  fast_moving_days int NOT NULL DEFAULT 30,
  predictive_stock_days int NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  tax_rate numeric(5,4) DEFAULT 0.0,
  custom_rules jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  address text,
  is_default boolean DEFAULT false,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, name)
);
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS locations_company_id_idx ON public.locations(company_id);

CREATE TABLE public.products (
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
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);


CREATE TABLE public.inventory (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  quantity int NOT NULL DEFAULT 0,
  cost int NOT NULL DEFAULT 0,
  price int,
  landed_cost int,
  on_order_quantity int NOT NULL DEFAULT 0,
  last_sold_date date,
  version int NOT NULL DEFAULT 1,
  deleted_at timestamptz,
  deleted_by uuid REFERENCES public.users(id),
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity int,
  last_sync_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, product_id, location_id)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);

CREATE TABLE public.vendors (
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
  UNIQUE(company_id, vendor_name)
);
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);

CREATE TABLE public.supplier_catalogs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  supplier_sku text,
  unit_cost int NOT NULL,
  moq int DEFAULT 1,
  lead_time_days int,
  is_active boolean DEFAULT true,
  UNIQUE(supplier_id, product_id)
);
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);

CREATE TABLE public.reorder_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
  rule_type text DEFAULT 'manual',
  min_stock int,
  max_stock int,
  reorder_quantity int,
  CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock),
  CHECK (reorder_quantity IS NULL OR reorder_quantity > 0),
  UNIQUE(company_id, product_id, location_id)
);
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);

CREATE TABLE public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);

CREATE TABLE public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES public.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sales_customer_id_idx ON public.sales(customer_id);

CREATE TABLE public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer NOT NULL
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);

CREATE SEQUENCE public.purchase_orders_po_number_seq;
CREATE TABLE public.purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
  po_number text NOT NULL DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000'),
  status public.po_status DEFAULT 'draft',
  order_date date NOT NULL,
  expected_date date,
  total_amount bigint NOT NULL DEFAULT 0,
  tax_amount bigint,
  shipping_cost bigint,
  notes text,
  requires_approval boolean DEFAULT false,
  approved_by uuid REFERENCES public.users(id),
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);

CREATE TABLE public.purchase_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity_ordered int NOT NULL,
  quantity_received int NOT NULL DEFAULT 0,
  unit_cost int NOT NULL,
  tax_rate numeric(5,4)
);
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);

CREATE TABLE public.inventory_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  product_id uuid NOT NULL REFERENCES public.products(id),
  location_id uuid NOT NULL REFERENCES public.locations(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES public.users(id),
  change_type text NOT NULL,
  quantity_change int NOT NULL,
  new_quantity int NOT NULL,
  related_id uuid, -- e.g., sale_id, po_id
  notes text
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_location_idx ON public.inventory_ledger(product_id, location_id);

CREATE TABLE public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_accessed_at timestamptz NOT NULL DEFAULT now(),
  is_starred boolean DEFAULT false
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS conversations_company_id_idx ON public.conversations(company_id);

CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  role public.message_role NOT NULL,
  content text NOT NULL,
  visualization jsonb,
  confidence numeric(3,2),
  assumptions text[],
  component text,
  component_props jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);

CREATE TABLE public.channel_fees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric(8, 6) NOT NULL,
  fixed_fee int NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);

CREATE TABLE public.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);

CREATE TABLE public.sync_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    status text NOT NULL,
    records_synced int,
    error_message text,
    started_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
);
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);

CREATE TABLE public.sync_state (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz NOT NULL DEFAULT now(),
    UNIQUE(integration_id, sync_type)
);
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

CREATE TABLE public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES public.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS audit_log_company_id_idx ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS audit_log_user_id_idx ON public.audit_log(user_id);

CREATE TABLE public.user_feedback (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL, -- e.g., 'anomaly_explanation', 'ai_suggestion'
    feedback text NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS user_feedback_company_id_idx ON public.user_feedback(company_id);


-- =============================================
--           MATERIALIZED VIEWS
-- =============================================
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost)::bigint AS inventory_value,
    COUNT(DISTINCT p.id) AS total_skus,
    SUM(CASE WHEN i.quantity < COALESCE(rr.min_stock, 0) THEN 1 ELSE 0 END) AS low_stock_count
FROM public.inventory i
JOIN public.products p ON i.product_id = p.id
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
WHERE i.deleted_at IS NULL
GROUP BY i.company_id;

ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;

CREATE MATERIALIZED VIEW public.customer_analytics_metrics AS
SELECT
    s.company_id,
    c.id AS customer_id,
    SUM(s.total_amount) AS total_spent,
    COUNT(s.id) AS total_orders
FROM public.sales s
JOIN public.customers c ON s.customer_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY s.company_id, c.id;

ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;


-- =============================================
--                 FUNCTIONS
-- =============================================

-- Helper function to get the current user's company_id
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid
$$;

-- Generic function to bump the updated_at timestamp
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Function to increment version and set updated_at on inventory updates
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

-- Trigger to handle new user signups
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
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  INSERT INTO public.companies (company_name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  INSERT INTO public.users (id, company_id, role, email)
  VALUES (new.id, new_company_id, 'Owner', new.email);
  
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
    ) || jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{role}',
      to_jsonb('Owner'::text)
    )
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Trigger to enforce message company_id matches its conversation
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

-- Function to safely batch upsert records in a transaction
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
  p_table_name text,
  p_records jsonb,
  p_conflict_columns text[]
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  table_regclass regclass;
BEGIN
  table_regclass := to_regclass(p_table_name);
  IF table_regclass IS NULL THEN
      RAISE EXCEPTION 'Table % not found.', p_table_name;
  END IF;

  EXECUTE format(
    'INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_recordset(null::%s, %L) ON CONFLICT (%s) DO UPDATE SET %s',
    table_regclass,
    (SELECT string_agg(quote_ident(key), ', ') FROM jsonb_object_keys(p_records -> 0)),
    (SELECT string_agg(quote_ident(key), ', ') FROM jsonb_object_keys(p_records -> 0)),
    table_regclass,
    p_records,
    array_to_string(p_conflict_columns, ', '),
    (SELECT string_agg(quote_ident(key) || ' = EXCLUDED.' || quote_ident(key), ', ') FROM jsonb_object_keys(p_records -> 0) WHERE key <> ALL(p_conflict_columns))
  );
END;
$$;

-- Function to record a sale and update inventory atomically
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
  total_amount_cents bigint;
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
      (j->>'product_id')::uuid,
      (j->>'location_id')::uuid,
      (j->>'quantity')::int,
      (j->>'unit_price')::int,
      inv.cost
    FROM jsonb_array_elements($1) AS j
    JOIN public.inventory inv
      ON inv.product_id  = (j->>'product_id')::uuid
     AND inv.location_id = (j->>'location_id')::uuid
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
  INTO total_amount_cents;

  SELECT cs.tax_rate INTO tax_rate
    FROM public.company_settings cs
   WHERE cs.company_id = p_company_id;
  tax_amount := total_amount_cents * COALESCE(tax_rate,0);

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
    total_amount_cents, tax_amount,
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

CREATE OR REPLACE FUNCTION public.refresh_materialized_views(
  p_company_id uuid,
  p_view_names text[]
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


-- =============================================
--                 TRIGGERS
-- =============================================

-- Attaches to auth.users table to handle new user setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger for inventory versioning
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();
  
-- Trigger for message company_id enforcement
DROP TRIGGER IF EXISTS trigger_enforce_message_company_id ON public.messages;
CREATE TRIGGER trigger_enforce_message_company_id
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();

-- Generic updated_at triggers
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


-- =============================================
--           ROW-LEVEL SECURITY (RLS)
-- =============================================

-- Policies for companies table
CREATE POLICY "Company members can view their own company"
  ON public.companies FOR SELECT
  USING (id = auth.company_id());

-- Policies for users table
CREATE POLICY "Users can view other members of their company"
  ON public.users FOR SELECT
  USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Owners can update their own company members"
  ON public.users FOR UPDATE
  USING (company_id = auth.company_id() AND (SELECT role FROM public.users WHERE id = auth.uid()) = 'Owner')
  WITH CHECK (company_id = auth.company_id());

-- Policies for company_settings table
CREATE POLICY "Company members can manage their own settings"
  ON public.company_settings FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for locations table
CREATE POLICY "Company members can manage their own locations"
  ON public.locations FOR ALL
  USING (company_id = auth.company_id() AND deleted_at IS NULL);

-- Policies for products table
CREATE POLICY "Company members can manage their own products"
  ON public.products FOR ALL
  USING (company_id = auth.company_id());

-- Policies for inventory table
CREATE POLICY "Company members can manage their own inventory"
  ON public.inventory FOR ALL
  USING (company_id = auth.company_id() AND deleted_at IS NULL);

-- Policies for vendors table
CREATE POLICY "Company members can manage their own vendors"
  ON public.vendors FOR ALL
  USING (company_id = auth.company_id() AND deleted_at IS NULL);

-- Policies for supplier_catalogs table
CREATE POLICY "Company members can manage their own supplier catalogs"
  ON public.supplier_catalogs FOR ALL
  USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));

-- Policies for reorder_rules table
CREATE POLICY "Company members can manage their own reorder rules"
  ON public.reorder_rules FOR ALL
  USING (company_id = auth.company_id());

-- Policies for customers table
CREATE POLICY "Company members can manage their own customers"
  ON public.customers FOR ALL
  USING (company_id = auth.company_id() AND deleted_at IS NULL);

-- Policies for sales table
CREATE POLICY "Company members can manage their own sales"
  ON public.sales FOR ALL
  USING (company_id = auth.company_id());

-- Policies for sale_items table
CREATE POLICY "Company members can manage their own sale items"
  ON public.sale_items FOR ALL
  USING (company_id = auth.company_id());

-- Policies for purchase_orders table
CREATE POLICY "Company members can manage their own purchase orders"
  ON public.purchase_orders FOR ALL
  USING (company_id = auth.company_id());

-- Policies for purchase_order_items table
CREATE POLICY "Company members can manage their own PO items"
  ON public.purchase_order_items FOR ALL
  USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));

-- Policies for inventory_ledger table
CREATE POLICY "Company members can view their own inventory ledger"
  ON public.inventory_ledger FOR SELECT
  USING (company_id = auth.company_id());

-- Policies for conversations table
CREATE POLICY "Users can manage their own conversations"
  ON public.conversations FOR ALL
  USING (user_id = auth.uid());

-- Policies for messages table
CREATE POLICY "Users can manage messages in their own conversations"
  ON public.messages FOR ALL
  USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
  
-- Policies for channel_fees table
CREATE POLICY "Company members can manage their own channel fees"
  ON public.channel_fees FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for integrations table
CREATE POLICY "Company members can manage their own integrations"
  ON public.integrations FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for sync_logs table
CREATE POLICY "Company members can view their own sync logs"
  ON public.sync_logs FOR ALL
  USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
  
-- Policies for sync_state table
CREATE POLICY "Company members can access their own sync state"
  ON public.sync_state FOR ALL
  USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
  
-- Policies for export_jobs table
CREATE POLICY "Company members can manage their own export jobs"
  ON public.export_jobs FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for audit_log table
CREATE POLICY "Company members can view their own audit log"
  ON public.audit_log FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for user_feedback table
CREATE POLICY "Users can manage their own feedback"
  ON public.user_feedback FOR ALL
  USING (company_id = auth.company_id());
  
-- Policies for materialized views
CREATE POLICY "Company members can view their own dashboard metrics"
  ON public.company_dashboard_metrics FOR SELECT
  USING (company_id = auth.company_id());
  
CREATE POLICY "Company members can view their own customer analytics"
  ON public.customer_analytics_metrics FOR SELECT
  USING (company_id = auth.company_id());


-- =============================================
--               DEFAULT GRANTS
-- =============================================

-- Grant all privileges on all tables in the public schema to the service_role
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant usage on all sequences to authenticated users
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant authenticated users permissions to call functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant authenticated users permissions on tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE ON FUNCTIONS TO authenticated;


-- Finally, refresh the materialized views for the first time
-- Note: This will only work if run by a user with sufficient permissions.
-- In a new Supabase project, the default 'postgres' user has this.
-- This part might be run manually after the initial schema setup.
-- SELECT public.refresh_materialized_views();
