-- InvoChat: Production-Ready Database Schema
-- Version: 4.0
-- Description: This script sets up the complete database schema for the InvoChat application,
-- including tables, roles, functions, triggers, and row-level security policies.

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

-- Create sequences for auto-incrementing user-friendly IDs
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;

----------------------------------------
-- TABLE DEFINITIONS
----------------------------------------

-- Stores basic company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

-- Stores company-specific business logic settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric(10,2) NOT NULL DEFAULT 3,
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

-- Stores core product definitions, independent of stock levels
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

-- Stores physical warehouse or stock-keeping locations
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
CREATE INDEX IF NOT EXISTS idx_locations_company_id ON public.locations(company_id);

-- Stores inventory levels for each product at each location
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0,
    price bigint,
    reorder_point integer,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    landed_cost bigint,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CONSTRAINT inventory_quantity_non_negative CHECK ((quantity >= 0)),
    CONSTRAINT on_order_quantity_non_negative CHECK ((on_order_quantity >= 0))
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_product_location ON public.inventory(company_id, product_id, location_id);

-- Stores supplier information
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, vendor_name)
);
CREATE INDEX IF NOT EXISTS idx_vendors_company_id ON public.vendors(company_id);

-- Stores supplier-specific product data like cost and lead time
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    supplier_id uuid NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    supplier_sku text,
    unit_cost bigint NOT NULL,
    moq integer DEFAULT 1,
    lead_time_days integer,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(supplier_id, product_id)
);

-- Stores product-specific rules for reordering
CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    location_id uuid,
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CONSTRAINT fk_reorder_rules_product FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT fk_reorder_rules_location FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_reorder_rules_company_product ON public.reorder_rules(company_id, product_id);

-- Stores purchase orders sent to suppliers
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000'),
    status public.po_status DEFAULT 'draft',
    order_date date DEFAULT CURRENT_DATE,
    expected_date date,
    total_amount bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
CREATE INDEX IF NOT EXISTS idx_po_company_supplier ON public.purchase_orders(company_id, supplier_id);

-- Stores line items for each purchase order
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint,
    tax_rate numeric(5,4),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(po_id, product_id)
);

-- Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text,
    external_id text,
    customer_name text NOT NULL,
    email text,
    status text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, email)
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);

-- Stores sales transactions
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id),
    sale_number text NOT NULL DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'),
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_created_at ON public.sales(company_id, created_at);

-- Stores line items for each sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
    UNIQUE(sale_id, product_id, location_id)
);

-- Stores chat conversation metadata
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Stores individual chat messages
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
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

-- Stores e-commerce integration details
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

-- Stores a complete audit trail of all inventory movements
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    location_id uuid,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text,
    CONSTRAINT fk_ledger_product FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    CONSTRAINT fk_ledger_location FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product_date ON public.inventory_ledger(company_id, product_id, created_at DESC);

-- Stores sales channel fees for accurate net margin calculation
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(8,6) NOT NULL,
    fixed_fee bigint NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);
CREATE INDEX IF NOT EXISTS channel_fees_company_id_idx ON public.channel_fees(company_id);

-- Stores jobs for exporting company data
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS export_jobs_company_id_idx ON public.export_jobs(company_id);

-- Generic audit log for important events
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_company_id_idx ON public.audit_log(company_id);
CREATE INDEX IF NOT EXISTS audit_log_user_id_idx ON public.audit_log(user_id);

-- Stores state for long-running integration syncs
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    PRIMARY KEY(integration_id, sync_type)
);

-- Logs the results of integration sync jobs
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Stores user feedback on AI features
CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_feedback_subject_idx ON public.user_feedback(subject_id, subject_type);


----------------------------------------
-- VIEWS FOR PERFORMANCE
----------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.product_id) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(CASE WHEN rr.min_stock IS NOT NULL AND i.quantity <= rr.min_stock AND i.quantity > 0 THEN 1 END) as low_stock_count
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
        COUNT(s.id) as total_orders
    FROM public.customers AS c
    JOIN public.sales AS s ON c.id = s.customer_id AND c.company_id = s.company_id
    WHERE c.deleted_at IS NULL
    GROUP BY c.company_id, c.id
)
SELECT
    cs.company_id,
    COUNT(cs.id) as total_customers,
    COUNT(*) FILTER (WHERE cs.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
    (SELECT COALESCE(AVG(total_amount), 0) FROM public.sales WHERE company_id = cs.company_id) AS average_lifetime_value,
    CASE WHEN COUNT(cs.id) > 0 THEN
        (COUNT(*) FILTER (WHERE cs.total_orders > 1))::numeric * 100 / COUNT(cs.id)::numeric
    ELSE 0 END as repeat_customer_rate
FROM customer_stats AS cs
GROUP BY cs.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_pkey ON public.customer_analytics_metrics(company_id);

----------------------------------------
-- FUNCTIONS & TRIGGERS
----------------------------------------

-- Helper function to securely get the company_id from the JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid
$$;

-- Trigger function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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
  
  -- Use the built-in admin function to update user metadata securely
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

-- Attach trigger to auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger function to auto-update 'updated_at' columns
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Trigger function to increment version and update timestamp on inventory
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

-- Apply triggers to tables
DROP TRIGGER IF EXISTS handle_inventory_update ON public.inventory;
CREATE TRIGGER handle_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  EXECUTE PROCEDURE public.increment_version();

-- List of tables to apply the updated_at trigger
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'company_settings', 'products', 'locations', 'vendors', 'supplier_catalogs',
            'reorder_rules', 'purchase_orders', 'purchase_order_items', 'customers', 'integrations'
        )
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trigger_%s_updated_at ON public.%I', t_name, t_name);
        EXECUTE format('CREATE TRIGGER trigger_%s_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at()', t_name, t_name);
    END LOOP;
END;
$$;

-- Advanced function to record a sale and update inventory transactionally
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
  new_customer_id uuid;
  total_amount_cents bigint;
  tax_rate       numeric;
  tax_amount_cents numeric;
  item_rec       record;
  tmp_table_name text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      product_name text,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP
  $fmt$, tmp_table_name);

  EXECUTE format($fmt$
    INSERT INTO %I (product_id, location_id, product_name, quantity, unit_price, cost_at_time)
    SELECT
      (item->>'product_id')::uuid,
      (item->>'location_id')::uuid,
      p.name,
      (item->>'quantity')::integer,
      (item->>'unit_price')::integer,
      i.cost
    FROM jsonb_array_elements($1) AS x(item)
    JOIN public.products p ON p.id = (x.item->>'product_id')::uuid
    JOIN public.inventory i ON i.product_id = p.id AND i.location_id = (x.item->>'location_id')::uuid AND i.company_id = $2
  $fmt$, tmp_table_name)
  USING p_sale_items, p_company_id;

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

  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp_table_name)
  INTO total_amount_cents;

  SELECT s.tax_rate INTO tax_rate FROM public.company_settings s WHERE s.company_id = p_company_id;
  tax_amount_cents := total_amount_cents * COALESCE(tax_rate,0);

  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id,email)
    DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer_id;
  END IF;

  INSERT INTO public.sales (
    company_id, customer_id, customer_name, customer_email, total_amount, tax_amount,
    payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id, new_customer_id, p_customer_name, p_customer_email, total_amount_cents, tax_amount_cents,
    p_payment_method, p_notes, p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  FOR item_rec IN EXECUTE format('SELECT * FROM %I', tmp_table_name)
  LOOP
    INSERT INTO public.sale_items (
      sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time
    )
    VALUES (
      new_sale.id, p_company_id, item_rec.product_id, item_rec.location_id,
      item_rec.quantity, item_rec.unit_price, item_rec.cost_at_time
    );

    UPDATE public.inventory
    SET
      quantity = quantity - item_rec.quantity,
      last_sold_date = CURRENT_DATE
    WHERE
      company_id  = p_company_id
      AND product_id  = item_rec.product_id
      AND location_id = item_rec.location_id;

    INSERT INTO public.inventory_ledger(
      company_id, product_id, location_id, change_type, quantity_change, new_quantity,
      related_id, notes, created_by
    )
    SELECT
      p_company_id, item_rec.product_id, item_rec.location_id,
      'sale', -item_rec.quantity, i.quantity, new_sale.id,
      'Sale #'||new_sale.sale_number, p_user_id
    FROM public.inventory i
    WHERE i.product_id=item_rec.product_id AND i.location_id=item_rec.location_id AND i.company_id=p_company_id;
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

----------------------------------------
-- ROW-LEVEL SECURITY (RLS)
----------------------------------------
-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Define RLS policies
DROP POLICY IF EXISTS "Company access" ON public.companies;
CREATE POLICY "Company access" ON public.companies FOR SELECT USING (id = auth.company_id());

DROP POLICY IF EXISTS "Company access" ON public.company_settings;
CREATE POLICY "Company access" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for products" ON public.products;
CREATE POLICY "Company access for products" ON public.products FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Company access for locations" ON public.locations;
CREATE POLICY "Company access for locations" ON public.locations FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Company access for inventory" ON public.inventory;
CREATE POLICY "Company access for inventory" ON public.inventory FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Company access for vendors" ON public.vendors;
CREATE POLICY "Company access for vendors" ON public.vendors FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Company access for supplier catalogs" ON public.supplier_catalogs;
CREATE POLICY "Company access for supplier catalogs" ON public.supplier_catalogs FOR ALL USING (supplier_id IN (SELECT id FROM public.vendors WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Company access for reorder rules" ON public.reorder_rules;
CREATE POLICY "Company access for reorder rules" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for purchase orders" ON public.purchase_orders;
CREATE POLICY "Company access for purchase orders" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for purchase order items" ON public.purchase_order_items;
CREATE POLICY "Company access for purchase order items" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Company access for customers" ON public.customers;
CREATE POLICY "Company access for customers" ON public.customers FOR ALL USING (company_id = auth.company_id() AND deleted_at IS NULL);

DROP POLICY IF EXISTS "Company access for sales" ON public.sales;
CREATE POLICY "Company access for sales" ON public.sales FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for sale items" ON public.sale_items;
CREATE POLICY "Company access for sale items" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for conversations" ON public.conversations;
CREATE POLICY "Company access for conversations" ON public.conversations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "User can manage their own messages" ON public.messages;
CREATE POLICY "User can manage their own messages" ON public.messages FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for integrations" ON public.integrations;
CREATE POLICY "Company access for integrations" ON public.integrations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for inventory ledger" ON public.inventory_ledger;
CREATE POLICY "Company access for inventory ledger" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for channel fees" ON public.channel_fees;
CREATE POLICY "Company access for channel fees" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for export jobs" ON public.export_jobs;
CREATE POLICY "Company access for export jobs" ON public.export_jobs FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for audit log" ON public.audit_log;
CREATE POLICY "Company access for audit log" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for sync state" ON public.sync_state;
CREATE POLICY "Company access for sync state" ON public.sync_state FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Company access for sync logs" ON public.sync_logs;
CREATE POLICY "Company access for sync logs" ON public.sync_logs FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Company access for user feedback" ON public.user_feedback;
CREATE POLICY "Company access for user feedback" ON public.user_feedback FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for dashboard metrics" ON public.company_dashboard_metrics;
CREATE POLICY "Company access for dashboard metrics" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Company access for customer analytics" ON public.customer_analytics_metrics;
CREATE POLICY "Company access for customer analytics" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());

-- RLS for Storage
CREATE POLICY "Public assets are publicly accessible" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

----------------------------------------
-- GRANTS
----------------------------------------
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Initial data refresh
SELECT public.refresh_materialized_views();
