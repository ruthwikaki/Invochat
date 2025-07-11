
-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Grant usage on the public schema to the anon and authenticated roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;

--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------
-- Define a custom type for user roles
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
-- Grant usage on custom types to the authenticated role
GRANT USAGE ON TYPE public.user_role TO authenticated;
GRANT USAGE ON TYPE public.po_status TO authenticated;
GRANT USAGE ON TYPE public.message_role TO authenticated;


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
    role public.user_role DEFAULT 'Member'::public.user_role,
    deleted_at timestamptz
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT products_company_id_sku_key UNIQUE (company_id, sku)
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false NOT NULL,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT locations_company_id_name_key UNIQUE (company_id, name)
);
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer DEFAULT 0 NOT NULL,
    cost integer DEFAULT 0 NOT NULL,
    price integer,
    landed_cost integer,
    on_order_quantity integer DEFAULT 0 NOT NULL,
    last_sold_date date,
    version integer DEFAULT 1 NOT NULL,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES public.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT inventory_company_id_product_id_location_id_key UNIQUE (company_id, product_id, location_id)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT vendors_company_id_vendor_name_key UNIQUE (company_id, vendor_name)
);
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer NOT NULL,
    moq integer DEFAULT 1 NOT NULL,
    lead_time_days integer,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT supplier_catalogs_supplier_id_product_id_key UNIQUE (supplier_id, product_id)
);
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    rule_type text DEFAULT 'manual'::text NOT NULL,
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT reorder_rules_check CHECK ((min_stock <= max_stock)),
    CONSTRAINT reorder_rules_company_id_product_id_location_id_key UNIQUE (company_id, product_id, location_id)
);
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    is_starred boolean DEFAULT false NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    last_accessed_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text NOT NULL,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence real,
    assumptions text[],
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT fk_messages_conv_company CHECK (true)
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    customer_name text,
    customer_email text,
    total_amount integer NOT NULL,
    tax_amount integer,
    payment_method text NOT NULL,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES public.users(id),
    external_id text,
    CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer NOT NULL
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status public.po_status DEFAULT 'draft'::public.po_status,
    order_date date NOT NULL,
    expected_date date,
    total_amount integer DEFAULT 0 NOT NULL,
    tax_amount integer,
    shipping_cost integer,
    notes text,
    requires_approval boolean DEFAULT false NOT NULL,
    approved_by uuid REFERENCES public.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost integer NOT NULL,
    tax_rate real
);
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES public.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee real DEFAULT 0 NOT NULL,
    fixed_fee integer DEFAULT 0 NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false NOT NULL,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sync_state (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT sync_state_integration_id_sync_type_key UNIQUE (integration_id, sync_type)
);
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    status text NOT NULL,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz
);
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    overstock_multiplier real DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate real,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    status text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- VIEWS & MATERIALIZED VIEWS
--------------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
 SELECT c.id AS company_id,
    COALESCE(sum(i.quantity * i.cost), 0::bigint) AS inventory_value,
    count(DISTINCT i.product_id) FILTER (WHERE i.quantity <= COALESCE(rr.min_stock, 0)) AS low_stock_count,
    count(DISTINCT i.product_id) AS total_skus
   FROM companies c
     LEFT JOIN inventory i ON c.id = i.company_id
     LEFT JOIN reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id AND i.company_id = rr.company_id
  GROUP BY c.id;
ALTER TABLE public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
 SELECT s.company_id,
    s.customer_id,
    sum(s.total_amount) AS total_spent,
    count(*) AS total_orders
   FROM sales s
  WHERE s.customer_id IS NOT NULL
  GROUP BY s.company_id, s.customer_id;
ALTER TABLE public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- INDEXES
--------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS users_company_id_idx ON public.users(company_id);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_company_id_idx ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_company_id_idx ON public.supplier_catalogs(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS reorder_rules_company_id_idx ON public.reorder_rules(company_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS conversations_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS conversations_company_id_idx ON public.conversations(company_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS customers_company_id_idx ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sales_customer_id_idx ON public.sales(customer_id);
CREATE INDEX IF NOT EXISTS sale_items_sale_id_idx ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS purchase_orders_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS purchase_orders_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_po_id_idx ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS purchase_order_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_product_id_location_id_idx ON public.inventory_ledger(company_id, product_id, location_id);
CREATE INDEX IF NOT EXISTS inventory_ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);
CREATE INDEX IF NOT EXISTS audit_log_company_id_idx ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS audit_log_user_id_idx ON public.audit_log(user_id);
CREATE INDEX IF NOT EXISTS user_feedback_company_id_idx ON public.user_feedback(company_id);
CREATE INDEX IF NOT EXISTS user_feedback_user_id_idx ON public.user_feedback(user_id);
CREATE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics(company_id);
CREATE INDEX IF NOT EXISTS customer_analytics_metrics_company_id_customer_id_idx ON public.customer_analytics_metrics(company_id, customer_id);

--------------------------------------------------------------------------------
-- HELPER & TRIGGER FUNCTIONS
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'
$$;

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
  
  -- Re-instated to prevent bad data. The signup form should enforce this.
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Insert a row into public.users
  INSERT INTO public.users (id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();


CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS trigger
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
DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_supplier_catalogs_updated_at ON public.supplier_catalogs;
CREATE TRIGGER trigger_supplier_catalogs_updated_at BEFORE UPDATE ON public.supplier_catalogs FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_reorder_rules_updated_at ON public.reorder_rules;
CREATE TRIGGER trigger_reorder_rules_updated_at BEFORE UPDATE ON public.reorder_rules FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_integrations_updated_at ON public.integrations;
CREATE TRIGGER trigger_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
DROP TRIGGER IF EXISTS trigger_company_settings_updated_at ON public.company_settings;
CREATE TRIGGER trigger_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  conv_company_id uuid;
BEGIN
  SELECT company_id INTO conv_company_id FROM public.conversations WHERE id = NEW.conversation_id;
  IF NEW.company_id != conv_company_id THEN
    RAISE EXCEPTION 'Message company_id does not match conversation company_id';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS check_message_company_id ON public.messages;
CREATE TRIGGER check_message_company_id
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();
  
--------------------------------------------------------------------------------
-- RLS POLICIES
--------------------------------------------------------------------------------
CREATE POLICY "Company members can view their company" ON public.companies FOR SELECT USING (id = auth.company_id());
CREATE POLICY "Users can manage their own user record" ON public.users FOR ALL USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "Company access for products" ON public.products FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for supplier catalogs" ON public.supplier_catalogs FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Company access for customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for sales" ON public.sales FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for po items" ON public.purchase_order_items FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access to channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access for sync state" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access for sync logs" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Company access to settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Company access for export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Company access to audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Company access to dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Company access to customer metrics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());


--------------------------------------------------------------------------------
-- STORED PROCEDURES / FUNCTIONS
--------------------------------------------------------------------------------
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
  total_amount_cents   bigint;
  tax_rate       numeric;
  tax_amount_cents     numeric;
  item_record       record;
  temp_table_name      text := 'sale_items_temp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  -- 1. Create a temporary table to hold processed sale items
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP;
  $fmt$, temp_table_name);

  -- 2. Populate the temporary table from the JSON payload
  EXECUTE format($sql$
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
     AND inv.company_id  = $2;
  $sql$, temp_table_name)
  USING p_sale_items, p_company_id;
  
  -- 3. Check for sufficient stock for all items in the transaction
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.inventory
      WHERE company_id  = p_company_id
        AND product_id  = item_record.product_id
        AND location_id = item_record.location_id
        AND quantity    >= item_record.quantity
    ) THEN
      RAISE EXCEPTION 'Insufficient stock for product % at location %',
        item_record.product_id, item_record.location_id;
    END IF;
  END LOOP;

  -- 4. Calculate total amount and tax
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', temp_table_name)
  INTO total_amount_cents;

  SELECT cs.tax_rate INTO tax_rate
  FROM public.company_settings cs
  WHERE cs.company_id = p_company_id;
  tax_amount_cents := total_amount_cents * COALESCE(tax_rate, 0);

  -- 5. Upsert customer record
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email)
    DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer;
  END IF;

  -- 6. Insert the main sale record
  INSERT INTO public.sales (
    company_id, customer_id, customer_name, customer_email, total_amount, tax_amount,
    payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id, new_customer, p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents,
    p_payment_method, p_notes, p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  -- 7. Insert sale items, update inventory, and create ledger entries
  FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
  LOOP
    INSERT INTO public.sale_items (
      sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time
    )
    VALUES (
      new_sale.id, p_company_id, item_record.product_id, item_record.location_id, item_record.quantity,
      item_record.unit_price, item_record.cost_at_time
    );

    UPDATE public.inventory
    SET
      quantity = quantity - item_record.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id  = p_company_id
      AND product_id  = item_record.product_id
      AND location_id = item_record.location_id;

    INSERT INTO public.inventory_ledger(
      company_id, product_id, location_id, change_type, quantity_change, new_quantity,
      related_id, notes, created_by
    )
    SELECT
      p_company_id, item_record.product_id, item_record.location_id, 'sale', -item_record.quantity,
      i.quantity, new_sale.id, 'Sale #' || new_sale.sale_number, p_user_id
    FROM public.inventory i
    WHERE i.product_id = item_record.product_id
      AND i.location_id = item_record.location_id
      AND i.company_id = p_company_id;
  END LOOP;

  -- 8. Refresh materialized views for dashboard updates
  PERFORM public.refresh_materialized_views(p_company_id);
  RETURN new_sale;
END;
$$;


--------------------------------------------------------------------------------
-- FINALIZATION
--------------------------------------------------------------------------------

-- Grant all privileges on all tables in the public schema to the service_role
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant usage on the public schema to the postgres user
GRANT USAGE ON SCHEMA public TO postgres;

-- Grant execute on all functions in the public schema to the authenticated and service_role roles
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

-- Setup default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;

-- Initial refresh of materialized views
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW public.customer_analytics_metrics;
END;
$$;

-- Note: The initial call to refresh is removed to avoid errors in a completely fresh database.
-- The function is now called from within transactionally-safe functions like record_sale_transaction.
