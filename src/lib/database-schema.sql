-- InvoChat Database Schema
-- Version: 2.0
-- Description: This script sets up the entire database, including tables,
-- functions, RLS policies, and initial data structures for a new InvoChat instance.
-- It is designed to be idempotent and can be run safely on a new or existing database.

-- =============================================
-- SECTION 1: EXTENSIONS & HELPER FUNCTIONS
-- =============================================
-- Enable necessary extensions.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgroonga;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Helper function to get the company_id from the current user's JWT claims.
-- This is a cornerstone of the multi-tenancy security model.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid);
$$;

-- Helper function to get the role from the current user's JWT claims.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::text);
$$;

-- =============================================
-- SECTION 2: DROP EXISTING OBJECTS (FOR IDEMPOTENCY)
-- =============================================
-- This section ensures the script can be re-run by cleaning up old objects first.
-- The order of operations is critical to avoid dependency errors.

DO $$
DECLARE
    r record;
BEGIN
    -- Drop all RLS policies on public tables
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
    END LOOP;
END $$;

DROP VIEW IF EXISTS public.product_variants_with_details;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid, uuid, text, text, text, jsonb[], text);
DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.get_dashboard_metrics(uuid, integer);
DROP FUNCTION IF EXISTS public.get_inventory_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_sales_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_customer_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_dead_stock_report(uuid);
DROP FUNCTION IF EXISTS public.detect_anomalies(uuid);
DROP FUNCTION IF EXISTS public.get_alerts(uuid);
DROP FUNCTION IF EXISTS public.get_reorder_suggestions(uuid);
DROP FUNCTION IF EXISTS public.get_supplier_performance_report(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_turnover(uuid, integer);
DROP FUNCTION IF EXISTS public.get_inventory_aging_report(uuid);
DROP FUNCTION IF EXISTS public.get_product_lifecycle_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_inventory_risk_report(uuid);
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_cash_flow_insights(uuid);
DROP FUNCTION IF EXISTS public.get_net_margin_by_channel(uuid, text);
DROP FUNCTION IF EXISTS public.get_sales_velocity(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
DROP FUNCTION IF EXISTS public.get_abc_analysis(uuid);
DROP FUNCTION IF EXISTS public.get_margin_trends(uuid);
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
DROP FUNCTION IF EXISTS public.batch_upsert_costs(jsonb[], uuid, uuid);
DROP FUNCTION IF EXISTS public.batch_upsert_suppliers(jsonb[], uuid, uuid);
DROP FUNCTION IF EXISTS public.batch_import_sales(jsonb[], uuid, uuid);
DROP FUNCTION IF EXISTS public.get_users_for_company(uuid);
DROP FUNCTION IF EXISTS public.remove_user_from_company(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_user_role_in_company(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.reconcile_inventory_from_integration(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.create_purchase_orders_from_suggestions(uuid, uuid, jsonb, uuid);
DROP FUNCTION IF EXISTS public.get_historical_sales_for_sku(uuid, text);

-- =============================================
-- SECTION 3: TABLE CREATION
-- =============================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days int NOT NULL DEFAULT 90,
    fast_moving_days int NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    predictive_stock_days int NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    custom_rules jsonb,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    fts_document tsvector,
    UNIQUE(company_id, external_product_id)
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- Stored in cents
    compare_at_price int, -- Stored in cents
    cost int, -- Stored in cents
    inventory_quantity int NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change int NOT NULL,
    new_quantity int NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders int DEFAULT 0,
    total_spent int DEFAULT 0, -- Stored in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal int NOT NULL DEFAULT 0,
    total_tax int DEFAULT 0,
    total_shipping int DEFAULT 0,
    total_discounts int DEFAULT 0,
    total_amount int NOT NULL, -- All monetary values stored in cents
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity int NOT NULL,
    price int NOT NULL,
    total_discount int DEFAULT 0,
    tax_amount int DEFAULT 0,
    cost_at_time int, -- Stored in cents
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft', -- e.g., Draft, Ordered, Partially Received, Received, Cancelled
    po_number text NOT NULL,
    total_cost int NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity int NOT NULL,
    cost int NOT NULL -- Stored in cents
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL, -- e.g., 'shopify', 'woocommerce'
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

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
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    UNIQUE (integration_id, webhook_id)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending',
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);


-- =============================================
-- SECTION 4: INDEXES
-- =============================================
-- Add indexes for performance on frequently queried columns.

-- For product/variant lookups
CREATE INDEX IF NOT EXISTS idx_product_variants_sku_company ON public.product_variants (sku, company_id);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products (company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants (product_id);
CREATE INDEX IF NOT EXISTS idx_products_fts_document ON public.products USING GIN (fts_document);


-- For order/sales filtering and sorting
CREATE INDEX IF NOT EXISTS idx_orders_company_id_created_at ON public.orders (company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items (variant_id);

-- For inventory history lookups
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id_created_at ON public.inventory_ledger (variant_id, created_at DESC);

-- For multi-tenancy lookups
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers (company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers (company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders (company_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations (company_id);


-- =============================================
-- SECTION 5: VIEWS
-- =============================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    pv.company_id,
    pv.sku,
    pv.title,
    p.title as product_title,
    p.status as product_status,
    p.product_type,
    p.image_url,
    pv.option1_name,
    pv.option1_value,
    pv.option2_name,
    pv.option2_value,
    pv.option3_name,
    pv.option3_value,
    pv.barcode,
    pv.price,
    pv.compare_at_price,
    pv.cost,
    pv.inventory_quantity,
    pv.location,
    pv.external_variant_id
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE
    pv.company_id = public.get_company_id();


-- =============================================
-- SECTION 6: DATABASE FUNCTIONS & TRIGGERS
-- =============================================

-- Function to set up a new user and their company.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    new_user_id uuid := auth.uid();
    new_user_email text := (SELECT email FROM auth.users WHERE id = new_user_id);
    company_name text := (SELECT raw_app_meta_data->>'company_name' FROM auth.users WHERE id = new_user_id);
    new_company_id uuid;
BEGIN
    -- Create a new company
    INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO new_company_id;

    -- Create a user profile in the public schema
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new_user_id, new_company_id, new_user_email, 'Owner');
    
    -- Update the user's app_metadata in the auth schema
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    WHERE id = new_user_id;
END;
$$;

-- Transactional function to record a sale and update inventory atomically.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid, -- Can be null for system-recorded sales
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_total_amount int := 0;
    item jsonb;
    v_variant_id uuid;
    v_product_id uuid;
    v_current_stock int;
    v_product_name text;
    v_variant_title text;
    v_cost_at_time int;
BEGIN
    -- Find or create the customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers
        WHERE company_id = p_company_id AND email = p_customer_email;

        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
            VALUES (p_company_id, p_customer_name, p_customer_email, NOW()::date)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Calculate total order amount
    FOREACH item IN ARRAY p_sale_items
    LOOP
        v_total_amount := v_total_amount + (item->>'quantity')::int * (item->>'unit_price')::int;
    END LOOP;

    -- Create the order
    INSERT INTO public.orders (company_id, customer_id, total_amount, order_number, notes, source_platform)
    VALUES (p_company_id, v_customer_id, v_total_amount, 'ORD-' || nextval('orders_order_number_seq'), p_notes, p_payment_method)
    RETURNING id INTO v_order_id;
    
    -- Process each line item
    FOREACH item IN ARRAY p_sale_items
    LOOP
        -- Find variant and lock the row to prevent race conditions
        SELECT id, product_id, inventory_quantity, cost, (SELECT title FROM products WHERE id=pv.product_id), title
        INTO v_variant_id, v_product_id, v_current_stock, v_cost_at_time, v_product_name, v_variant_title
        FROM public.product_variants pv
        WHERE company_id = p_company_id AND sku = (item->>'sku')
        FOR UPDATE;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', item->>'sku';
        END IF;

        -- Update inventory quantity
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - (item->>'quantity')::int
        WHERE id = v_variant_id;

        -- Create order line item
        INSERT INTO public.order_line_items (order_id, company_id, product_id, variant_id, product_name, variant_title, sku, quantity, price, cost_at_time)
        VALUES (v_order_id, p_company_id, v_product_id, v_variant_id, v_product_name, v_variant_title, (item->>'sku'), (item->>'quantity')::int, (item->>'unit_price')::int, v_cost_at_time);

        -- Record in inventory ledger
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -(item->>'quantity')::int, v_current_stock - (item->>'quantity')::int, v_order_id, 'Order #' || (SELECT order_number FROM orders WHERE id=v_order_id));

    END LOOP;
    
    RETURN v_order_id;
END;
$$;


-- Function to parse and record an order from a platform like Shopify or WooCommerce
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id uuid;
    v_order_id uuid;
    v_order_number text;
    v_external_order_id text;
    v_customer_email text;
    v_customer_name text;
    line_item jsonb;
    v_variant_id uuid;
    v_product_id uuid;
    v_current_stock int;
    v_sku text;
    v_cost_at_time int;
BEGIN
    -- Extract common fields based on platform
    IF p_platform = 'shopify' THEN
        v_external_order_id := p_order_payload->>'id';
        v_order_number := p_order_payload->>'name';
        v_customer_email := p_order_payload->'customer'->>'email';
        v_customer_name := COALESCE(p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', 'Guest');
    ELSIF p_platform = 'woocommerce' THEN
        v_external_order_id := p_order_payload->>'id';
        v_order_number := p_order_payload->>'number';
        v_customer_email := p_order_payload->'billing'->>'email';
        v_customer_name := COALESCE(p_order_payload->'billing'->>'first_name' || ' ' || p_order_payload->'billing'->>'last_name', 'Guest');
    ELSE
        RAISE EXCEPTION 'Unsupported platform: %', p_platform;
    END IF;

    -- Check if order already exists
    IF EXISTS (SELECT 1 FROM public.orders WHERE company_id = p_company_id AND external_order_id = v_external_order_id) THEN
        RETURN; -- Skip if already processed
    END IF;

    -- Find or create customer
    IF v_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers WHERE company_id = p_company_id AND email = v_customer_email;
        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
            VALUES (p_company_id, v_customer_name, v_customer_email, (p_order_payload->>'created_at')::date)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Create order
    INSERT INTO public.orders (company_id, external_order_id, order_number, customer_id, total_amount, subtotal, total_tax, total_shipping, total_discounts, financial_status, fulfillment_status, source_platform, created_at)
    VALUES (p_company_id, v_external_order_id, v_order_number, v_customer_id, 
            (p_order_payload->>'total_price')::numeric * 100,
            (p_order_payload->>'subtotal_price')::numeric * 100,
            (p_order_payload->>'total_tax')::numeric * 100,
            (p_order_payload->>'total_shipping_price_set'->'shop_money'->>'amount')::numeric * 100,
            (p_order_payload->>'total_discounts')::numeric * 100,
            p_order_payload->>'financial_status',
            p_order_payload->>'fulfillment_status',
            p_platform,
            (p_order_payload->>'created_at')::timestamptz
           )
    RETURNING id INTO v_order_id;
    
    -- Create order line items and update inventory
    FOR line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        v_sku := COALESCE(line_item->>'sku', p_platform || '-' || (line_item->>'id'));

        -- Lock variant row
        SELECT id, product_id, inventory_quantity, cost INTO v_variant_id, v_product_id, v_current_stock, v_cost_at_time
        FROM public.product_variants WHERE company_id = p_company_id AND sku = v_sku FOR UPDATE;
        
        IF v_variant_id IS NULL THEN
            RAISE WARNING 'SKU % not found for order line item %. Skipping.', v_sku, line_item->>'id';
            CONTINUE;
        END IF;

        INSERT INTO public.order_line_items (order_id, company_id, product_id, variant_id, product_name, variant_title, sku, quantity, price, cost_at_time, external_line_item_id)
        VALUES (v_order_id, p_company_id, v_product_id, v_variant_id, line_item->>'name', line_item->>'variant_title', v_sku, (line_item->>'quantity')::int, (line_item->>'price')::numeric * 100, v_cost_at_time, line_item->>'id');

        UPDATE public.product_variants SET inventory_quantity = inventory_quantity - (line_item->>'quantity')::int WHERE id = v_variant_id;
        
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, v_variant_id, 'sale', -(line_item->>'quantity')::int, v_current_stock - (line_item->>'quantity')::int, v_order_id, 'Order #' || v_order_number);
    END LOOP;
END;
$$;

-- =============================================
-- SECTION 7: ROW-LEVEL SECURITY (RLS)
-- =============================================

-- Procedure to enable RLS and create a standard policy for a table
CREATE OR REPLACE PROCEDURE enable_rls_on_table(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', p_table_name);
    EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())', p_table_name);
END;
$$;

-- Function to apply RLS to all relevant tables
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    r record;
BEGIN
    -- Tables with a direct company_id
    FOR r IN (
        SELECT table_name FROM information_schema.columns 
        WHERE table_schema = 'public' AND column_name = 'company_id'
        GROUP BY table_name
    ) LOOP
        CALL enable_rls_on_table(r.table_name);
    END LOOP;
    
    -- Special policy for the 'companies' table itself
    ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Allow access to own company" ON public.companies FOR ALL
    USING (id = public.get_company_id())
    WITH CHECK (id = public.get_company_id());
END;
$$;

-- Drop old policies before applying new ones to ensure idempotency
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS ' || quote_ident(r.policyname) || ' ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Apply the RLS policies
CALL apply_rls_policies();

-- Special policy for purchase_order_line_items, which links through purchase_orders
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow access based on parent PO" ON public.purchase_order_line_items FOR ALL
USING (
    company_id = public.get_company_id()
);
