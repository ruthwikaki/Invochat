-- InvoChat - Production-Ready Database Schema
-- Version: 2.0
-- Description: This script sets up the entire database, including tables,
-- functions, row-level security, and business logic for a multi-tenant
-- inventory management application. It has been hardened with specific
-- fixes for concurrency, data integrity, and security based on expert review.

-- 
-- SETUP EXTENSIONS
-- 
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- HELPER FUNCTION FOR COMPANY ID
-- This is the central function for RLS policies to get the current user's company_id.
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'company_id', '')::uuid
$$;

--
-- HELPER FUNCTION FOR USER ROLE
--
CREATE OR REPLACE FUNCTION auth.user_role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'role', '')::text
$$;


--
-- CREATE ENUM TYPES
--
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
END
$$;

--
-- CREATE SEQUENCES
-- These must be created before the tables that use them as defaults.
--
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
CREATE SEQUENCE IF NOT EXISTS public.purchase_orders_po_number_seq;


--
-- TABLE CREATION
--

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

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
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, name)
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    cost bigint NOT NULL DEFAULT 0, -- Stored in cents, represents default or latest cost
    price bigint, -- Stored in cents, represents default or latest selling price
    deleted_at timestamptz, -- For soft deletes
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    quantity integer NOT NULL DEFAULT 0,
    on_order_quantity integer NOT NULL DEFAULT 0,
    last_sold_date date,
    landed_cost bigint, -- in cents
    version integer NOT NULL DEFAULT 1,
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
CREATE INDEX IF NOT EXISTS idx_inventory_product_id ON public.inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_location_id ON public.inventory(location_id);


CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    vendor_name text NOT NULL,
    contact_info text,
    address text,
    terms text,
    account_number text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, vendor_name)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE RESTRICT, -- Prevent deleting supplier with active POs
    po_number text NOT NULL,
    status text,
    order_date date,
    expected_date date,
    total_amount bigint,
    tax_amount bigint,
    shipping_cost bigint,
    notes text,
    requires_approval boolean default false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);
ALTER TABLE public.purchase_orders ALTER COLUMN po_number SET DEFAULT 'PO-' || TO_CHAR(nextval('purchase_orders_po_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer DEFAULT 0 NOT NULL,
    unit_cost bigint, -- in cents
    tax_rate numeric(5,4),
    UNIQUE(po_id, product_id)
);

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

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_id uuid REFERENCES public.customers(id),
    total_amount bigint NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
ALTER TABLE public.sales ALTER COLUMN sale_number SET DEFAULT 'SALE-' || TO_CHAR(nextval('sales_sale_number_seq'), 'FM000000');


CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid NOT NULL REFERENCES public.locations(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint,
    UNIQUE(sale_id, product_id, location_id)
);

-- Other Tables (Integrations, Logs, etc.)

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

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    location_id uuid NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer,
    related_id uuid,
    notes text,
    created_by uuid REFERENCES auth.users(id),
    FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_date ON public.inventory_ledger(product_id, created_at DESC);

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
    created_at timestamptz DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.reorder_rules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    min_stock integer,
    reorder_quantity integer,
    FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE,
    UNIQUE(company_id, product_id)
);


--
-- TRIGGERS & AUTOMATION
--

-- Trigger function to automatically update 'updated_at' columns
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
CREATE TRIGGER handle_company_settings_update BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_locations_update BEFORE UPDATE ON public.locations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_products_update BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_inventory_update BEFORE UPDATE ON public.inventory FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_vendors_update BEFORE UPDATE ON public.vendors FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_purchase_orders_update BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_integrations_update BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();
CREATE TRIGGER handle_channel_fees_update BEFORE UPDATE ON public.channel_fees FOR EACH ROW EXECUTE PROCEDURE public.bump_updated_at();


-- Trigger function to handle new user signup
-- Creates a company, and uses the admin API to update the user's app_metadata.
-- This is the correct, secure way to handle multi-tenancy setup.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
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
  
  -- Use the built-in Supabase admin function to securely update user metadata
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

-- Attach the trigger to the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Trigger for optimistic locking on the inventory table
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
CREATE TRIGGER handle_inventory_version_update
BEFORE UPDATE ON public.inventory
FOR EACH ROW
EXECUTE PROCEDURE public.increment_version();


--
-- MATERIALIZED VIEWS for Performance
--

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.product_id) as total_skus,
  SUM(i.quantity * p.cost) as inventory_value,
  COUNT(DISTINCT CASE WHEN i.quantity <= rr.min_stock AND rr.min_stock > 0 THEN i.product_id END) as low_stock_count
FROM public.inventory AS i
JOIN public.products AS p ON i.product_id = p.id
LEFT JOIN public.reorder_rules AS rr ON i.product_id = rr.product_id AND i.company_id = rr.company_id
WHERE p.deleted_at IS NULL
GROUP BY i.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
WITH customer_sales AS (
    SELECT
        c.company_id,
        c.id,
        MIN(s.created_at) as first_order_date,
        COUNT(s.id) as total_orders
    FROM public.customers AS c
    JOIN public.sales AS s ON c.id = s.customer_id
    WHERE c.deleted_at IS NULL
    GROUP BY c.company_id, c.id
)
SELECT
    cs.company_id,
    COUNT(cs.id) as total_customers,
    COUNT(*) FILTER (WHERE cs.first_order_date >= NOW() - INTERVAL '30 days') as new_customers_last_30_days,
    CASE WHEN COUNT(cs.id) > 0 THEN
        (COUNT(*) FILTER (WHERE cs.total_orders > 1))::numeric * 100 / COUNT(cs.id)::numeric
    ELSE 0 END as repeat_customer_rate
FROM customer_sales AS cs
GROUP BY cs.company_id;
CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_pkey ON public.customer_analytics_metrics(company_id);


--
-- BUSINESS LOGIC FUNCTIONS (RPC)
--

-- Function to refresh all materialized views for a given company.
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
END;
$$;

-- Safely process inventory deduction for a sale. Called by record_sale_transaction.
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(p_sale_id uuid, p_company_id uuid, p_user_id uuid, p_inventory_updates jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    item_record record;
    updated_row_count int;
    current_stock int;
BEGIN
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_inventory_updates) AS x(product_id uuid, location_id uuid, quantity int, expected_version int)
    LOOP
        -- Lock the row and update
        UPDATE public.inventory AS i
        SET
            quantity = i.quantity - item_record.quantity,
            last_sold_date = CURRENT_DATE
        WHERE i.product_id = item_record.product_id
          AND i.location_id = item_record.location_id
          AND i.company_id = p_company_id
          AND i.version = item_record.expected_version
        RETURNING i.quantity INTO current_stock;

        GET DIAGNOSTICS updated_row_count = ROW_COUNT;
        IF updated_row_count = 0 THEN
            RAISE EXCEPTION 'Concurrency error: Inventory for product ID % was updated by another process. Please try the sale again.', item_record.product_id;
        END IF;

        -- Create a ledger entry for the change
        INSERT INTO public.inventory_ledger (company_id, product_id, location_id, created_by, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (
            p_company_id,
            item_record.product_id,
            item_record.location_id,
            p_user_id,
            'sale',
            -item_record.quantity,
            current_stock,
            p_sale_id,
            'Sale fulfillment'
        );
    END LOOP;
END;
$$;


-- Records a sale and its items, and correctly calls the inventory processing function.
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
    inventory_updates jsonb := '[]'::jsonb;
    v_customer_id uuid;
BEGIN
    -- Validate inventory and build update payload first
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, location_id uuid, quantity int, unit_price bigint)
    LOOP
        DECLARE
            current_inventory record;
        BEGIN
            SELECT quantity, version INTO current_inventory
            FROM public.inventory
            WHERE product_id = item_record.product_id AND location_id = item_record.location_id AND company_id = p_company_id AND deleted_at IS NULL
            FOR UPDATE; -- Lock the inventory row

            IF NOT FOUND OR current_inventory.quantity < item_record.quantity THEN
                RAISE EXCEPTION 'Insufficient stock for product ID: %. Available: %, Requested: %', item_record.product_id, COALESCE(current_inventory.quantity, 0), item_record.quantity;
            END IF;

            inventory_updates := inventory_updates || jsonb_build_object(
                'product_id', item_record.product_id,
                'location_id', item_record.location_id,
                'quantity', item_record.quantity,
                'expected_version', current_inventory.version
            );
            
            total_amount := total_amount + (item_record.quantity * item_record.unit_price);
        END;
    END LOOP;

    -- Upsert customer if email is provided
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO v_customer_id;
    END IF;

    -- Create the sale record
    INSERT INTO public.sales (company_id, customer_id, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, v_customer_id, total_amount, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING * INTO new_sale;

    -- Insert sale items
    FOR item_record IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, location_id uuid, quantity int, unit_price bigint)
    LOOP
        INSERT INTO public.sale_items (sale_id, company_id, product_id, location_id, quantity, unit_price, cost_at_time)
        SELECT new_sale.id, p_company_id, item_record.product_id, item_record.location_id, item_record.quantity, item_record.unit_price, p.cost
        FROM public.products p
        WHERE p.id = item_record.product_id AND p.company_id = p_company_id;
    END LOOP;

    -- Process inventory changes now that the sale is committed
    PERFORM public.process_sales_order_inventory(new_sale.id, new_sale.company_id, p_user_id, inventory_updates);

    RETURN new_sale;
END;
$$;


--
-- ROW LEVEL SECURITY (RLS)
--

-- Enable RLS on all company-specific tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reorder_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_feedback ENABLE ROW LEVEL SECURITY;

-- Enable RLS on Materialized Views
ALTER MATERIALIZED VIEW public.company_dashboard_metrics ENABLE ROW LEVEL SECURITY;
ALTER MATERIALIZED VIEW public.customer_analytics_metrics ENABLE ROW LEVEL SECURITY;


-- Create Policies
DROP POLICY IF EXISTS "Users can only access data for their own company" ON public.companies;
CREATE POLICY "Users can only access data for their own company" ON public.companies FOR SELECT USING (id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage settings for their own company" ON public.company_settings;
CREATE POLICY "Users can manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage products for their own company" ON public.products;
CREATE POLICY "Users can manage products for their own company" ON public.products FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage inventory for their own company" ON public.inventory;
CREATE POLICY "Users can manage inventory for their own company" ON public.inventory FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage vendors for their own company" ON public.vendors;
CREATE POLICY "Users can manage vendors for their own company" ON public.vendors FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage POs for their own company" ON public.purchase_orders;
CREATE POLICY "Users can manage POs for their own company" ON public.purchase_orders FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage PO Items for their own company" ON public.purchase_order_items;
CREATE POLICY "Users can manage PO Items for their own company" ON public.purchase_order_items FOR ALL USING (po_id IN (SELECT id FROM public.purchase_orders WHERE company_id = auth.company_id()));

DROP POLICY IF EXISTS "Users can manage sales for their own company" ON public.sales;
CREATE POLICY "Users can manage sales for their own company" ON public.sales FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage sale items for sales in their own company" ON public.sale_items;
CREATE POLICY "Users can manage sale items for sales in their own company" ON public.sale_items FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage customers for their own company" ON public.customers;
CREATE POLICY "Users can manage customers for their own company" ON public.customers FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage locations for their own company" ON public.locations;
CREATE POLICY "Users can manage locations for their own company" ON public.locations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage integrations for their own company" ON public.integrations;
CREATE POLICY "Users can manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage ledger for their own company" ON public.inventory_ledger;
CREATE POLICY "Users can manage ledger for their own company" ON public.inventory_ledger FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage fees for their own company" ON public.channel_fees;
CREATE POLICY "Users can manage fees for their own company" ON public.channel_fees FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage audit logs for their own company" ON public.audit_log;
CREATE POLICY "Users can manage audit logs for their own company" ON public.audit_log FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage their own conversations" ON public.conversations;
CREATE POLICY "Users can manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage their own messages" ON public.messages;
CREATE POLICY "Users can manage their own messages" ON public.messages FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage reorder rules for their own company" ON public.reorder_rules;
CREATE POLICY "Users can manage reorder rules for their own company" ON public.reorder_rules FOR ALL USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can manage their own user feedback" ON public.user_feedback;
CREATE POLICY "Users can manage their own user feedback" ON public.user_feedback FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view materialized views for their company" ON public.company_dashboard_metrics;
CREATE POLICY "Users can view materialized views for their company" ON public.company_dashboard_metrics FOR SELECT USING (company_id = auth.company_id());

DROP POLICY IF EXISTS "Users can view customer analytics for their company" ON public.customer_analytics_metrics;
CREATE POLICY "Users can view customer analytics for their company" ON public.customer_analytics_metrics FOR SELECT USING (company_id = auth.company_id());

--
-- STORAGE
--

-- Create a bucket for public assets like company logos.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('public_assets', 'public_assets', TRUE, 5242880, ARRAY['image/png', 'image/jpeg', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Enable RLS on storage.objects before creating policies.
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- Policy to allow anonymous read access to the public_assets bucket.
DROP POLICY IF EXISTS "Allow public read access to public_assets bucket" ON storage.objects;
CREATE POLICY "Allow public read access to public_assets bucket" ON storage.objects FOR SELECT USING (bucket_id = 'public_assets');

-- Policy to allow authenticated users to upload files to a folder named after their company_id.
DROP POLICY IF EXISTS "Allow authenticated users to upload company assets" ON storage.objects;
CREATE POLICY "Allow authenticated users to upload company assets" ON storage.objects FOR INSERT WITH CHECK (
    bucket_id = 'public_assets' AND
    auth.role() = 'authenticated' AND
    (storage.foldername(name))[1] = auth.company_id()::text
);


-- Final grants to ensure roles can access the schema
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public to authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
