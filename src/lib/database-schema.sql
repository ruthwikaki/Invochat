
-- ### InvoChat Database Schema ###
-- This script is designed to be run once on a fresh Supabase project.
-- It sets up all necessary tables, functions, security policies, and triggers.

-- --- 1. Extensions & Initial Setup ---
-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- --- 2. Custom Types ---
-- Define custom ENUM types for consistent roles and statuses.
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


-- --- 3. Table Definitions ---
-- All tables are created here, before any functions that might depend on them.

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Extend Supabase's auth.users table with custom fields
ALTER TABLE auth.users
ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES public.companies(id),
ADD COLUMN IF NOT EXISTS role public.user_role;

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    UNIQUE(company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz,
    UNIQUE(company_id, name)
);

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
    UNIQUE(company_id, product_id, location_id)
);

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
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost integer NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, supplier_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CHECK (min_stock IS NULL OR max_stock IS NULL OR min_stock <= max_stock)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status public.po_status DEFAULT 'draft',
    order_date date NOT NULL,
    expected_date date,
    total_amount integer NOT NULL DEFAULT 0,
    tax_amount integer,
    shipping_cost integer,
    notes text,
    requires_approval boolean NOT NULL DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
CREATE SEQUENCE IF NOT EXISTS purchase_orders_po_number_seq;
ALTER TABLE public.purchase_orders
  ALTER COLUMN po_number
  SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer NOT NULL DEFAULT 0,
    unit_cost integer NOT NULL,
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.customers (
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

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    customer_name text,
    customer_email text,
    total_amount integer NOT NULL,
    tax_amount integer,
    payment_method text NOT NULL,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE SEQUENCE IF NOT EXISTS sales_sale_number_seq;

CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer,
    UNIQUE(sale_id, product_id)
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false
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
    confidence real,
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL UNIQUE REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

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

CREATE TABLE IF NOT EXISTS public.sync_state (
  integration_id uuid PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  last_processed_cursor text,
  last_update timestamptz NOT NULL DEFAULT now(),
  UNIQUE(integration_id, sync_type)
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

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric NOT NULL,
  fixed_fee integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    file_path text,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.user_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  subject_id text NOT NULL,
  subject_type text NOT NULL,
  feedback text NOT NULL, -- 'helpful' or 'unhelpful'
  created_at timestamptz NOT NULL DEFAULT now()
);


-- --- 4. Indexes ---
-- Add indexes for performance on frequently queried columns.
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE INDEX IF NOT EXISTS inventory_product_id_idx ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS inventory_location_id_idx ON public.inventory(location_id);
CREATE INDEX IF NOT EXISTS vendors_company_id_idx ON public.vendors(company_id);
CREATE INDEX IF NOT EXISTS supplier_catalogs_product_id_idx ON public.supplier_catalogs(product_id);
CREATE INDEX IF NOT EXISTS reorder_rules_product_id_idx ON public.reorder_rules(product_id);
CREATE INDEX IF NOT EXISTS po_company_id_idx ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS po_supplier_id_idx ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS po_items_product_id_idx ON public.purchase_order_items(product_id);
CREATE INDEX IF NOT EXISTS sales_company_id_idx ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS sale_items_company_id_idx ON public.sale_items(company_id);
CREATE INDEX IF NOT EXISTS sale_items_product_id_idx ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS convos_user_id_idx ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS messages_company_id_idx ON public.messages(company_id);
CREATE INDEX IF NOT EXISTS integrations_company_id_idx ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS sync_logs_integration_id_idx ON public.sync_logs(integration_id);
CREATE INDEX IF NOT EXISTS ledger_company_prod_loc_idx ON public.inventory_ledger(company_id, product_id, location_id);
CREATE INDEX IF NOT EXISTS ledger_company_id_idx ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

-- --- 5. Helper & Trigger Functions ---
-- These functions encapsulate business logic and are used by triggers.
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

  UPDATE auth.users
  SET
    company_id = new_company_id,
    role = 'Owner'
  WHERE id = new.id;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

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
CREATE TRIGGER trigger_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at
  BEFORE UPDATE ON public.locations
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at
  BEFORE UPDATE ON public.vendors
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();
  
DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at
  BEFORE UPDATE ON public.purchase_orders
  FOR EACH ROW
  EXECUTE PROCEDURE public.bump_updated_at();
  
CREATE OR REPLACE FUNCTION public.enforce_message_company_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  conversation_company_id uuid;
BEGIN
  SELECT company_id INTO conversation_company_id FROM public.conversations WHERE id = NEW.conversation_id;
  IF NEW.company_id IS DISTINCT FROM conversation_company_id THEN
    RAISE EXCEPTION 'Message company_id must match its conversation''s company_id.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_enforce_message_company ON public.messages;
CREATE TRIGGER trigger_enforce_message_company
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE PROCEDURE public.enforce_message_company_id();

-- --- 6. Security Policies (RLS) ---
-- Enable RLS and define policies for all user-facing tables.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::json->>'company_id', '')::uuid;
$$;

CREATE POLICY "Allow company access" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Allow company access" ON public.products FOR ALL USING (company_id = auth.company_id()) WITH CHECK (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.supplier_catalogs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.purchase_order_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Allow company access" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Allow company access" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));
CREATE POLICY "Allow company access" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());


-- --- 7. Materialized Views for Performance ---
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  c.id as company_id,
  COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
  COALESCE(COUNT(DISTINCT i.product_id), 0) AS total_skus,
  COALESCE(SUM(CASE WHEN rr.min_stock IS NOT NULL AND i.quantity < rr.min_stock THEN 1 ELSE 0 END), 0) AS low_stock_count
FROM public.companies c
LEFT JOIN public.inventory i ON c.id = i.company_id AND i.deleted_at IS NULL
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id
GROUP BY c.id;

CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_company_id_idx ON public.company_dashboard_metrics(company_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
  s.company_id,
  COUNT(DISTINCT s.customer_id) as total_customers,
  SUM(s.total_amount) as total_revenue
FROM public.sales s
WHERE s.customer_id IS NOT NULL
GROUP BY s.company_id;

CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_company_id_idx ON public.customer_analytics_metrics(company_id);

-- Apply RLS to the materialized views
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow company access to dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Allow company access to customer metrics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());

-- --- 8. RPC Functions for Business Logic ---
-- These functions are called from server-side code (e.g., Server Actions).

CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'card',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    temp_table_name text;
    item_record RECORD;
    new_customer_id uuid;
    total_amount_cents bigint;
    company_tax_rate numeric;
    tax_amount_cents numeric;
    new_sale_id uuid;
    new_sale public.sales;
BEGIN
    temp_table_name := 'sale_items_temp_' || replace(gen_random_uuid()::text, '-', '');

    EXECUTE format('
        CREATE TEMP TABLE %I (
            product_id uuid,
            product_name text,
            quantity int,
            unit_price int,
            location_id uuid
        ) ON COMMIT DROP;',
        temp_table_name
    );
    
    EXECUTE format('
        INSERT INTO %I (product_id, product_name, quantity, unit_price, location_id)
        SELECT 
            (x->>''product_id'')::uuid,
            x->>''product_name'',
            (x->>''quantity'')::int,
            (x->>''unit_price'')::int,
            (x->>''location_id'')::uuid
        FROM jsonb_array_elements($1) AS x;',
        temp_table_name
    ) USING p_sale_items;

    FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
    LOOP
        PERFORM 1 FROM public.inventory
        WHERE product_id = item_record.product_id
          AND company_id = p_company_id
          AND location_id = item_record.location_id
          AND quantity >= item_record.quantity
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient stock for product % at the specified location.', item_record.product_name;
        END IF;
    END LOOP;

    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', temp_table_name)
    INTO total_amount_cents;

    SELECT tax_rate INTO company_tax_rate FROM public.company_settings WHERE company_id = p_company_id;
    tax_amount_cents := total_amount_cents * COALESCE(company_tax_rate, 0);

    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO new_customer_id FROM public.customers WHERE email = p_customer_email AND company_id = p_company_id;
        IF new_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email)
            VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
            RETURNING id INTO new_customer_id;
        END IF;
    END IF;
    
    INSERT INTO public.sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'), new_customer_id, p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;
    new_sale_id := new_sale.id;

    FOR item_record IN EXECUTE format('SELECT * FROM %I', temp_table_name)
    LOOP
        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE company_id = p_company_id AND product_id = item_record.product_id AND location_id = item_record.location_id;

        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price)
        VALUES (new_sale_id, p_company_id, item_record.product_id, item_record.quantity, item_record.unit_price);
        
        INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, related_id, notes)
        SELECT p_company_id, item_record.product_id, item_record.location_id, p_user_id, 'sale', -item_record.quantity, i.quantity, new_sale_id, 'Sale #' || new_sale.sale_number
        FROM public.inventory i
        WHERE i.product_id = item_record.product_id AND i.location_id = item_record.location_id AND i.company_id = p_company_id;
    END LOOP;

    RETURN new_sale;
END;
$$;


CREATE OR REPLACE FUNCTION public.check_inventory_references(p_company_id uuid, p_product_ids uuid[])
RETURNS TABLE(product_id uuid)
LANGUAGE sql
AS $$
  SELECT product_id FROM public.purchase_order_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids)
  UNION
  SELECT product_id FROM public.sale_items WHERE company_id = p_company_id AND product_id = ANY(p_product_ids);
$$;

-- --- 9. Permissions & Grants ---
-- Grant usage on schemas and types
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT USAGE ON TYPE public.user_role TO authenticated;

-- Grant permissions on tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;

-- Grant permissions on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant execute on functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Ensure future objects get permissions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON TYPES TO authenticated;

-- Grant permissions to Supabase-internal roles
GRANT USAGE ON SCHEMA public TO postgres, anon, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, service_role;

ALTER USER supabase_admin SET search_path TO "$user",public,auth;

-- Grant permissions on materialized views
GRANT SELECT ON public.company_dashboard_metrics TO authenticated;
GRANT SELECT ON public.customer_analytics_metrics TO authenticated;

-- --- 10. Finalization ---
-- Refresh materialized views to ensure they are populated on initial setup.
SELECT public.refresh_materialized_views();

-- Log the successful completion of the script
DO $$
BEGIN
  RAISE NOTICE 'InvoChat schema setup complete.';
END
$$;
