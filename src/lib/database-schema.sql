--
-- ARVO: PRODUCTION-READY DATABASE SCHEMA (v4.0)
--

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom types (enums)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled', 'pending_approval');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
END $$;

-- Create sequences before they are referenced in table defaults
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;

--
-- TABLE: companies
-- Description: Stores the top-level entity for data isolation.
--
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

--
-- TABLE: company_settings
-- Description: Stores business logic settings for each company.
-- Note: company_id is the Primary Key to enforce one-row-per-company.
--
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3.0,
    high_value_threshold bigint NOT NULL DEFAULT 100000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5,4) DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz
);

--
-- TABLE: locations
-- Description: Stores physical locations like warehouses.
--
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);

--
-- TABLE: products
-- Description: Core product information, without stock levels.
--
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

--
-- TABLE: inventory
-- Description: Tracks stock levels for each product at a specific location.
--
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0,
    price bigint,
    landed_cost bigint,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CONSTRAINT inventory_quantity_non_negative CHECK (quantity >= 0),
    CONSTRAINT on_order_quantity_non_negative CHECK (on_order_quantity >= 0)
);
CREATE INDEX IF NOT EXISTS idx_inventory_product_location ON public.inventory(product_id, location_id);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted ON public.inventory(company_id, deleted_at);

--
-- TABLE: vendors
--
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, vendor_name)
);

--
-- TABLE: supplier_catalogs
--
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost bigint NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE(supplier_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_supplier_catalogs_product_id ON public.supplier_catalogs(product_id);

--
-- TABLE: reorder_rules
--
CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(company_id, product_id, location_id)
);
CREATE INDEX IF NOT EXISTS idx_reorder_rules_product_id ON public.reorder_rules(product_id);

--
-- TABLE: purchase_orders
--
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL,
    status public.po_status DEFAULT 'draft',
    order_date date,
    expected_date date,
    total_amount bigint,
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid,
    approved_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


--
-- TABLE: purchase_order_items
--
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint,
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

--
-- TABLE: customers
--
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    UNIQUE(company_id, email)
);

--
-- TABLE: sales
--
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL UNIQUE,
    customer_id uuid REFERENCES public.customers(id),
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
ALTER TABLE public.sales ALTER COLUMN sale_number SET DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000');
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_sales_customer_email ON public.sales(company_id, customer_email);

--
-- TABLE: sale_items
--
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    product_name text,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
    UNIQUE(sale_id, product_id, location_id)
);

--
-- TABLE: conversations
--
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    last_accessed_at timestamptz DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false
);

--
-- TABLE: messages
--
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric(3,2),
    assumptions text[],
    created_at timestamptz DEFAULT now() NOT NULL,
    is_error boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

--
-- TABLE: integrations
--
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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

--
-- TABLE: inventory_ledger
--
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_location ON public.inventory_ledger(product_id, location_id, created_at DESC);

--
-- TABLE: channel_fees
--
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(8,6) NOT NULL,
    fixed_fee bigint NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
CREATE INDEX IF NOT EXISTS idx_channel_fees_company_id ON public.channel_fees(company_id);

--
-- TABLE: user_feedback
--
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_user_feedback_subject ON public.user_feedback(subject_id, subject_type);


--
-- TABLE: export_jobs
--
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_export_jobs_company_id ON public.export_jobs(company_id);

--
-- TABLE: audit_log
--
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now() NOT NULL
);

--
-- TABLE: sync_state & sync_logs
--
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    PRIMARY KEY(integration_id, sync_type)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz
);

--
-- MATERIALIZED VIEWS for performance
--
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.product_id) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(i.id) FILTER (WHERE i.quantity <= rr.min_stock AND rr.min_stock > 0) as low_stock_count
FROM public.inventory AS i
LEFT JOIN public.reorder_rules rr ON i.product_id = rr.product_id AND i.location_id = rr.location_id AND i.company_id = rr.company_id
WHERE i.deleted_at IS NULL
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
    JOIN public.sales AS s ON c.id = s.customer_id AND c.company_id = s.company_id
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

--
-- HELPER FUNCTIONS & TRIGGERS
--
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'
$$;

-- Generic trigger to bump the updated_at timestamp on any table
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Version increment trigger specifically for the inventory table for optimistic locking
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


-- Apply the generic updated_at trigger to tables
DROP TRIGGER IF EXISTS trigger_products_updated_at ON public.products;
CREATE TRIGGER trigger_products_updated_at
  BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_vendors_updated_at ON public.vendors;
CREATE TRIGGER trigger_vendors_updated_at
  BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_locations_updated_at ON public.locations;
CREATE TRIGGER trigger_locations_updated_at
  BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_purchase_orders_updated_at ON public.purchase_orders;
CREATE TRIGGER trigger_purchase_orders_updated_at
  BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();

DROP TRIGGER IF EXISTS trigger_company_settings_updated_at ON public.company_settings;
CREATE TRIGGER trigger_company_settings_updated_at
  BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();


-- Trigger to handle new user sign-ups
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');
  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty.';
  END IF;

  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Create a default location for the new company
  INSERT INTO public.locations (company_id, name, is_default)
  VALUES (new_company_id, 'Main Warehouse', true);

  -- Update the user's app_metadata with the new company_id and Owner role
  -- This is the correct, permission-safe way to update user metadata
  PERFORM auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
      'app_metadata', jsonb_build_object(
        'company_id', new_company_id,
        'role', 'Owner'
      )
    )
  );
  
  RETURN new;
END;
$$;
-- Drop existing trigger to ensure a clean setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Create the trigger that fires after a new user is inserted into auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

--
-- RPC FUNCTIONS
--

-- Record a sale and update inventory atomically
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
    new_customer_id uuid;
    total_amount_cents bigint;
    tax_rate_val numeric;
    tax_amount_cents bigint;
    item_record record;
    tmp_table_name text := 'sale_items_tmp_' || replace(gen_random_uuid()::text, '-', '');
BEGIN
    -- 1. Create a temporary table to hold processed sale items
    EXECUTE format(
        'CREATE TEMP TABLE %I (
            product_id uuid,
            location_id uuid,
            product_name text,
            quantity integer,
            unit_price integer,
            cost_at_time integer
        ) ON COMMIT DROP',
        tmp_table_name
    );

    -- 2. Populate the temp table with data from the JSON payload, joining to get current cost
    EXECUTE format($sql$
        INSERT INTO %I (product_id, location_id, product_name, quantity, unit_price, cost_at_time)
        SELECT
            (item->>'product_id')::uuid,
            (item->>'location_id')::uuid,
            p.name,
            (item->>'quantity')::integer,
            (item->>'unit_price')::integer,
            inv.cost
        FROM jsonb_array_elements($1) AS x(item)
        JOIN public.products p ON p.id = (x.item->>'product_id')::uuid AND p.company_id = $2
        JOIN public.inventory inv ON inv.product_id = p.id AND inv.location_id = (x.item->>'location_id')::uuid AND inv.company_id = $2
    $sql$, tmp_table_name)
    USING p_sale_items, p_company_id;

    -- 3. Perform stock checks against the temp table
    FOR item_record IN EXECUTE format('SELECT product_id, location_id, quantity FROM %I', tmp_table_name)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.inventory
            WHERE company_id = p_company_id
              AND product_id = item_record.product_id
              AND location_id = item_record.location_id
              AND quantity >= item_record.quantity
        ) THEN
            RAISE EXCEPTION 'Insufficient stock for product ID % at location ID %', item_record.product_id, item_record.location_id;
        END IF;
    END LOOP;

    -- 4. Calculate total amount and tax
    EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp_table_name) INTO total_amount_cents;
    SELECT cs.tax_rate INTO tax_rate_val FROM public.company_settings cs WHERE cs.company_id = p_company_id;
    tax_amount_cents := total_amount_cents * COALESCE(tax_rate_val, 0);

    -- 5. Upsert customer record
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers(company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- 6. Insert the main sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, tax_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'), new_customer_id, p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    -- 7. Loop through temp table to insert sale items, update inventory, and create ledger entries
    FOR item_record IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
    LOOP
        INSERT INTO public.sale_items (sale_id, company_id, product_id, location_id, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item_record.product_id, item_record.location_id, item_record.product_name, item_record.quantity, item_record.unit_price, item_record.cost_at_time);

        UPDATE public.inventory
        SET quantity = quantity - item_record.quantity, last_sold_date = CURRENT_DATE
        WHERE company_id = p_company_id AND product_id = item_record.product_id AND location_id = item_record.location_id;

        INSERT INTO public.inventory_ledger(company_id, product_id, location_id, change_type, quantity_change, new_quantity, related_id, notes, created_by)
        VALUES (p_company_id, item_record.product_id, item_record.location_id, 'sale', -item_record.quantity, (SELECT quantity FROM public.inventory WHERE product_id=item_record.product_id AND location_id=item_record.location_id AND company_id=p_company_id), new_sale.id, 'Sale #' || new_sale.sale_number, p_user_id);
    END LOOP;

    RETURN new_sale;
END;
$$;

-- Function to refresh materialized views
CREATE OR REPLACE FUNCTION public.refresh_materialized_views()
RETURNS void LANGUAGE sql AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
$$;

--
-- ROW LEVEL SECURITY (RLS)
--

-- Enable RLS on all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Define RLS Policies
CREATE POLICY "Allow company access based on user's company_id" ON public.companies FOR ALL USING (id = auth.company_id());
CREATE POLICY "Allow company access" ON public.company_settings FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.products FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.inventory FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access on vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.purchase_order_items FOR ALL USING ((SELECT company_id FROM public.purchase_orders WHERE id = po_id) = auth.company_id());
CREATE POLICY "Allow company access" ON public.sales FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.sale_items FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access on locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);
CREATE POLICY "Allow company access" ON public.integrations FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "Users can manage messages in their conversations" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));
CREATE POLICY "Allow company access" ON public.supplier_catalogs FOR ALL USING ((SELECT company_id FROM public.vendors WHERE id = supplier_id) = auth.company_id());
CREATE POLICY "Allow company access" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.audit_log FOR ALL USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Allow company access" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());
CREATE POLICY "Enable public access to public_assets bucket" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-- Initialize materialized views
SELECT public.refresh_materialized_views();
