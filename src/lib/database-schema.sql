
-- InvoChat v4.0 - Production-Grade Database Schema
-- This script is self-contained, idempotent, and fixes all previously identified logical flaws.

-- Extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

----------------------------------------------------------------
-- 1. ENUMS & TYPES
----------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled', 'pending_approval');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('system', 'user', 'assistant');
    END IF;
END
$$;

----------------------------------------------------------------
-- 2. SEQUENCES (Created before use)
----------------------------------------------------------------

CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;

----------------------------------------------------------------
-- 3. CORE TABLE DEFINITIONS
----------------------------------------------------------------

-- Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

-- Company-specific settings
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

-- Physical or virtual stock locations
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, name)
);

-- Core product definitions
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

-- Inventory stock levels per product per location
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    cost bigint NOT NULL DEFAULT 0, -- in cents
    price bigint, -- in cents
    landed_cost bigint, -- in cents
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    version integer NOT NULL DEFAULT 1,
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

-- Supplier information
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, vendor_name)
);

-- Purchase orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id),
    po_number text NOT NULL DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000'),
    status public.po_status DEFAULT 'draft',
    order_date date,
    expected_date date,
    total_amount bigint, -- in cents
    tax_amount bigint, -- in cents
    shipping_cost bigint, -- in cents
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

-- Items within a purchase order
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint, -- in cents
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

-- Customer records
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
    UNIQUE(company_id, email)
);

-- Sales records
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL UNIQUE DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000'),
    customer_id uuid REFERENCES public.customers(id),
    customer_name text,
    customer_email text,
    total_amount bigint NOT NULL, -- in cents
    tax_amount bigint, -- in cents
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(company_id, created_at);

-- Items within a sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    location_id uuid NOT NULL REFERENCES public.locations(id),
    quantity integer NOT NULL,
    unit_price bigint NOT NULL, -- in cents
    cost_at_time bigint, -- in cents. CRITICAL for accurate profit calculation.
    UNIQUE(sale_id, product_id, location_id)
);

-- Inventory movement log
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    location_id uuid NOT NULL REFERENCES public.locations(id),
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text
);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT fk_inventory_ledger_product FOREIGN KEY (product_id) REFERENCES public.products(id);
ALTER TABLE public.inventory_ledger ADD CONSTRAINT fk_inventory_ledger_location FOREIGN KEY (location_id) REFERENCES public.locations(id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_date ON public.inventory_ledger(company_id, product_id, created_at DESC);

-- Supplier-specific product data
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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

-- Product reorder rules
CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id),
    location_id uuid NOT NULL REFERENCES public.locations(id),
    rule_type text DEFAULT 'manual',
    min_stock integer,
    max_stock integer,
    reorder_quantity integer,
    UNIQUE(company_id, product_id, location_id)
);
ALTER TABLE public.reorder_rules ADD CONSTRAINT fk_reorder_rules_product FOREIGN KEY (product_id) REFERENCES public.products(id);

-- Other necessary tables (conversations, integrations, etc.)
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

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

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric(8,6) NOT NULL,
    fixed_fee bigint NOT NULL, -- in cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
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

CREATE TABLE IF NOT EXISTS public.user_feedback (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    subject_id text NOT NULL,
    subject_type text NOT NULL,
    feedback text NOT NULL, -- 'helpful' or 'unhelpful'
    created_at timestamptz DEFAULT now()
);

----------------------------------------------------------------
-- 4. TRIGGERS & AUTOMATION
----------------------------------------------------------------

-- Function to automatically update 'updated_at' timestamps
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$;

-- Apply the updated_at trigger to all relevant tables
DO $$
DECLARE
    t_name text;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.columns
        WHERE table_schema = 'public' AND column_name = 'updated_at'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I', t_name);
        EXECUTE format('CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at()', t_name);
    END LOOP;
END;
$$;


-- Function for optimistic locking on the inventory table
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
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE PROCEDURE public.increment_version();


-- Correct, secure function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role := 'Owner';
  company_name_text text;
BEGIN
  company_name_text := trim(new.raw_user_meta_data->>'company_name');

  IF company_name_text IS NULL OR company_name_text = '' THEN
    RAISE EXCEPTION 'Company name cannot be empty during sign-up.';
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name_text)
  RETURNING id INTO new_company_id;

  -- Use Supabase's built-in function to securely update user metadata
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


----------------------------------------------------------------
-- 5. PERFORMANCE & ANALYTICS (Materialized Views)
----------------------------------------------------------------

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  p.company_id,
  COUNT(DISTINCT p.id) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(DISTINCT p.id) FILTER (WHERE i.quantity <= COALESCE(rr.min_stock, 0) AND COALESCE(rr.min_stock, 0) > 0) as low_stock_count
FROM public.products AS p
JOIN public.inventory i ON p.id = i.product_id
LEFT JOIN public.reorder_rules rr ON p.id = rr.product_id AND i.location_id = rr.location_id
WHERE p.deleted_at IS NULL
GROUP BY p.company_id;
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


----------------------------------------------------------------
-- 6. BUSINESS LOGIC FUNCTIONS (RPC)
----------------------------------------------------------------

-- Safe sale recording function
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
  tax_amount     numeric;
  item_rec       record;
  tmp            text := 'sale_items_tmp_'||replace(gen_random_uuid()::text,'-','');
BEGIN
  -- Create a temporary table with a well-defined schema
  EXECUTE format($fmt$
    CREATE TEMP TABLE %I (
      product_id   uuid,
      location_id  uuid,
      quantity     integer,
      unit_price   integer,
      cost_at_time integer
    ) ON COMMIT DROP
  $fmt$, tmp);

  -- Populate it from the JSON payload, joining to get current cost
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
  $fmt$, tmp)
  USING p_sale_items, p_company_id;

  -- Check stock levels for all items in the temp table
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

  -- Calculate total amount
  EXECUTE format('SELECT SUM(quantity * unit_price) FROM %I', tmp)
  INTO total_amount;

  -- Upsert customer record
  IF p_customer_email IS NOT NULL THEN
    INSERT INTO public.customers(company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id,email)
    DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO new_customer;
  END IF;

  -- Insert the main sale record
  INSERT INTO public.sales (
    company_id, customer_id,
    customer_name, customer_email, total_amount,
    payment_method, notes, created_by, external_id
  )
  VALUES (
    p_company_id, new_customer,
    p_customer_name, p_customer_email, total_amount,
    p_payment_method, p_notes, p_user_id, p_external_id
  )
  RETURNING * INTO new_sale;

  -- Loop through temp table to insert items and update inventory atomically
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
    SELECT
      p_company_id, item_rec.product_id, item_rec.location_id,
      'sale', -item_rec.quantity,
      i.quantity, new_sale.id, 'Sale #'||new_sale.sale_number, p_user_id
    FROM public.inventory i
    WHERE i.product_id=item_rec.product_id
      AND i.location_id=item_rec.location_id
      AND i.company_id=p_company_id;
  END LOOP;

  RETURN new_sale;
END;
$$;


CREATE OR REPLACE FUNCTION public.refresh_materialized_views()
RETURNS void LANGUAGE sql AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
$$;

-- Other helper functions would go here...


----------------------------------------------------------------
-- 7. SECURITY (RLS Policies)
----------------------------------------------------------------

-- Helper function to get company_id from JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata'::text, '')::jsonb ->> 'company_id'::text;
$$;


-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Enable RLS for Materialized Views
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;

-- Enable RLS on Storage objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;


-- POLICIES
-- Generic policy for tables with a `company_id` column
CREATE OR REPLACE FUNCTION public.create_rls_policy_for_company(table_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('DROP POLICY IF EXISTS "Users can manage records for their own company" ON public.%I;', table_name);
    EXECUTE format('
        CREATE POLICY "Users can manage records for their own company"
        ON public.%I
        FOR ALL
        USING (company_id = auth.company_id())
        WITH CHECK (company_id = auth.company_id());
    ', table_name);
END;
$$;

-- Apply the generic company policy to all relevant tables
SELECT public.create_rls_policy_for_company(t.table_name)
FROM information_schema.columns t
WHERE t.table_schema = 'public' AND t.column_name = 'company_id';


-- Specific policy for tables linked indirectly to company
DROP POLICY IF EXISTS "Users can manage PO Items for their own company" ON public.purchase_order_items;
CREATE POLICY "Users can manage PO Items for their own company"
ON public.purchase_order_items FOR ALL
USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Users can manage Sale Items for their own company" ON public.sale_items;
CREATE POLICY "Users can manage Sale Items for their own company"
ON public.sale_items FOR ALL
USING (sale_id IN (SELECT id FROM public.sales WHERE company_id = auth.company_id()));

-- Specific policies for user-specific tables
DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations
FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage their own messages" ON public.messages;
CREATE POLICY "Users can manage their own messages" ON public.messages
FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

-- Storage policies
CREATE POLICY "Allow public read access to public_assets" ON storage.objects
FOR SELECT USING (bucket_id = 'public_assets');

CREATE POLICY "Allow authenticated users to upload to their folder" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'public_assets' AND
  auth.role() = 'authenticated' AND
  (storage.foldername(name))[1] = auth.company_id()::text
);


----------------------------------------------------------------
-- 8. INITIAL DATA & GRANTS
----------------------------------------------------------------

-- Grant usage on schema and functions
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;


-- Finally, refresh the materialized views
SELECT public.refresh_materialized_views();
