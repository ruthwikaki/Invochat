--
-- Universal ARVO Migration Script
--
-- This script is designed to upgrade an existing ARVO database schema
-- to the latest version. It fixes security vulnerabilities, improves
-- performance, and adds new features. It is designed to be idempotent,
-- meaning it is safe to run multiple times.
--
-- PRE-MIGRATION STEPS:
-- 1. Take a full backup of your database before running this script.
--
-- HOW TO RUN:
-- 1. Go to your Supabase project dashboard.
-- 2. Navigate to the SQL Editor.
-- 3. Paste the entire contents of this file into the editor.
-- 4. Click "Run".
--
-- Version: 2024-07-26
--

-- === I. Drop Dependent Views & Functions for Restructuring ===
-- We must drop views and functions that depend on tables or columns
-- we need to alter. They will be recreated later in the script.

DROP VIEW IF EXISTS public.product_variants_with_details;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.customers_view;

DROP FUNCTION IF EXISTS public.get_user_company_id(uuid);
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();


-- === II. Create Missing Tables & Add Columns ===

-- Create the 'orders' table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer DEFAULT 0 NOT NULL,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);

-- Create the 'order_line_items' table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

-- Add missing columns to 'product_variants'
ALTER TABLE public.product_variants
    ADD COLUMN IF NOT EXISTS option1_name text,
    ADD COLUMN IF NOT EXISTS option1_value text,
    ADD COLUMN IF NOT EXISTS option2_name text,
    ADD COLUMN IF NOT EXISTS option2_value text,
    ADD COLUMN IF NOT EXISTS option3_name text,
    ADD COLUMN IF NOT EXISTS option3_value text,
    ADD COLUMN IF NOT EXISTS compare_at_price integer,
    ADD COLUMN IF NOT EXISTS location text,
    ADD COLUMN IF NOT EXISTS barcode text;

-- Add idempotency key to purchase orders to prevent duplicates
ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS idempotency_key uuid;


-- === III. Alter Existing Tables & Add Constraints ===
-- Drop and recreate foreign keys and constraints to ensure they are correct.

-- product_variants table
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;

-- Ensure SKU is not nullable on order_line_items
ALTER TABLE public.order_line_items ALTER COLUMN sku SET NOT NULL;

-- inventory_ledger table
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_variant_id_fkey;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE;


-- === IV. Update Security Functions & Policies ===

-- Overhaul get_company_id to use app_metadata for security
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    current_setting('request.jwt.claims', true)::jsonb ->> 'company_id',
    (SELECT raw_app_meta_data ->> 'company_id' FROM auth.users WHERE id = auth.uid())
  )::uuid;
$$;

-- Overhaul handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_user_email text;
  v_company_name text;
BEGIN
  -- Extract details from the new auth.users record
  v_user_email := new.email;
  v_company_name := new.raw_app_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding user profile in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, v_user_email, 'Owner');

  -- Update the user's app_metadata in auth.users with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Recreate the trigger for new user handling
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Procedure to dynamically enable RLS on all relevant tables
DROP PROCEDURE IF EXISTS enable_rls_on_table(text);
CREATE OR REPLACE PROCEDURE enable_rls_for_all_tables()
LANGUAGE plpgsql
AS $$
DECLARE
    tbl record;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl.tablename);
        EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY;', tbl.tablename);
        
        -- Drop old policies if they exist before creating new ones
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON public.%I;', tbl.tablename);

        -- Create a secure, standardized policy
        EXECUTE format('CREATE POLICY "Allow all access to own company data" ON public.%I FOR ALL USING (company_id = public.get_company_id());', tbl.tablename);
    END LOOP;
END;
$$;

-- Execute the RLS procedure
CALL enable_rls_for_all_tables();

-- Drop the procedure as it's no longer needed after execution
DROP PROCEDURE enable_rls_for_all_tables();


-- === V. Update Database Functions for New Features ===

-- Update record_sale_transaction for race condition safety
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
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
    v_variant_id uuid;
    v_current_quantity int;
    v_cost_at_time int;
    item jsonb;
    v_sku text;
    v_quantity int;
BEGIN
    -- Upsert customer and get ID
    INSERT INTO public.customers (company_id, customer_name, email)
    VALUES (p_company_id, p_customer_name, p_customer_email)
    ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
    RETURNING id INTO v_customer_id;

    -- Create Order
    INSERT INTO public.orders (company_id, customer_id, total_amount, external_order_id, source_platform, order_number)
    VALUES (
        p_company_id,
        v_customer_id,
        (SELECT sum((i->>'unit_price')::int * (i->>'quantity')::int) FROM unnest(p_sale_items) i),
        p_external_id,
        'manual',
        'SALE-' || nextval('orders_order_number_seq'::regclass)
    )
    RETURNING id INTO v_order_id;

    -- Process line items
    FOREACH item IN ARRAY p_sale_items
    LOOP
        v_sku := item->>'sku';
        v_quantity := (item->>'quantity')::int;

        -- LOCK THE VARIANT ROW to prevent race conditions
        SELECT id, inventory_quantity, cost INTO v_variant_id, v_current_quantity, v_cost_at_time
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_sku
        FOR UPDATE;

        IF v_variant_id IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', v_sku;
        END IF;

        -- Update inventory quantity
        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - v_quantity
        WHERE id = v_variant_id;

        -- Insert line item
        INSERT INTO public.order_line_items (order_id, company_id, product_id, variant_id, sku, product_name, quantity, price, cost_at_time)
        SELECT v_order_id, p_company_id, pv.product_id, v_variant_id, v_sku, p.title, v_quantity, (item->>'unit_price')::int, v_cost_at_time
        FROM public.product_variants pv JOIN public.products p ON pv.product_id = p.id
        WHERE pv.id = v_variant_id;
        
        -- Insert into inventory ledger
        INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, v_variant_id, 'sale', -v_quantity, v_current_quantity - v_quantity, v_order_id);
    END LOOP;

    RETURN v_order_id;
END;
$$;


-- === VI. Recreate Views & Indexes ===

-- Recreate customers_view
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.total_orders,
    c.total_spent,
    c.first_order_date,
    c.created_at
FROM public.customers c;

-- Recreate product_variants_with_details view
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.id,
    pv.product_id,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;

-- Recreate orders_view
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email as customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.source_name,
    o.tags,
    o.notes,
    o.cancelled_at,
    o.created_at
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;

-- Add necessary indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_created_at ON public.inventory_ledger(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- Final log to confirm completion
SELECT 'Migration script completed successfully.';
