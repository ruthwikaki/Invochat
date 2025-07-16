
-- Drop the trigger and function if they exist from a previous version to prevent conflicts.
-- This is crucial for making the script runnable on existing databases.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Drop existing RLS policies before creating new ones to ensure updates are applied.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' DISABLE ROW LEVEL SECURITY';
        -- Drop all existing policies for the table
        EXECUTE 'DO $POL$ BEGIN FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = ''' || r.tablename || ''' AND schemaname = ''public'') LOOP EXECUTE ''DROP POLICY IF EXISTS '' || quote_ident(r.policyname) || '' ON public.' || quote_ident(r.tablename) || '''; END LOOP; END $POL$;';
    END LOOP;
END $$;


-- =============================================
-- SECTION 1: CORE TABLES
-- Defines the foundational tables for the application.
-- =============================================

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5
);

-- =============================================
-- SECTION 2: PRODUCT & INVENTORY TABLES
-- Tables related to products, variants, and stock levels.
-- =============================================

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
    fts_document tsvector,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
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
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, sku)
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================
-- SECTION 3: SALES & CUSTOMER TABLES
-- Tables for tracking orders, customers, and related data.
-- =============================================

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    UNIQUE(company_id, external_order_id)
);

-- FIX: product_id and variant_id are now NOT NULL to enforce data integrity.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);

-- =============================================
-- SECTION 4: SUPPLIERS & PURCHASING TABLES
-- =============================================

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id),
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- FIX: company_id added for proper RLS.
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    cost integer NOT NULL
);


-- =============================================
-- SECTION 5: INTEGRATIONS & MISC TABLES
-- =============================================

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform text NOT NULL,
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
    user_id uuid NOT NULL REFERENCES auth.users(id),
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

-- =============================================
-- SECTION 6: INDEXES & OPTIMIZATIONS
-- =============================================

CREATE INDEX IF NOT EXISTS idx_orders_company_created ON public.orders(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_variants_company_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_created ON public.inventory_ledger(variant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_products_fts ON public.products USING gin(fts_document);


-- =============================================
-- SECTION 7: DATABASE FUNCTIONS & LOGIC
-- =============================================

-- Safely drop existing function before creating
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company_name from metadata, if it exists
  v_company_name := new.raw_app_meta_data->>'company_name';

  -- If company_name is provided, create a new company
  IF v_company_name IS NOT NULL AND v_company_name != '' THEN
    INSERT INTO public.companies (name)
    VALUES (v_company_name)
    RETURNING id INTO v_company_id;
  ELSE
    -- If no company name, try to get company_id from invite
    v_company_id := (new.raw_app_meta_data->>'company_id')::uuid;
    IF v_company_id IS NULL THEN
      -- This path should ideally not be taken in normal flow.
      -- A user should either be creating a company or accepting an invite.
      -- As a fallback, create a company with a default name.
      INSERT INTO public.companies (name)
      VALUES (new.email || '''s Company')
      RETURNING id INTO v_company_id;
    END IF;
  END IF;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the definitive company_id
  -- This makes it available in the JWT for RLS policies
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;


-- =============================================
-- SECTION 8: VIEWS
-- For simplified data access and analytics.
-- =============================================

CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT 
    pv.id,
    pv.product_id,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    pv.company_id,
    pv.sku,
    pv.title,
    pv.inventory_quantity,
    pv.price,
    pv.cost,
    pv.location
FROM public.product_variants pv
JOIN public.products p ON pv.product_id = p.id;

-- =============================================
-- SECTION 9: SECURITY (ROW-LEVEL SECURITY)
-- =============================================

-- Helper function to get the current user's company_id from their JWT
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid)
$$;

-- A procedure to dynamically apply RLS policies to all tables in the public schema
CREATE OR REPLACE PROCEDURE apply_rls_policies()
LANGUAGE plpgsql
AS $$
DECLARE
    table_name_ident regclass;
BEGIN
    FOR table_name_ident IN (SELECT table_name::regclass FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE') LOOP
        -- Enable RLS on the table
        EXECUTE 'ALTER TABLE ' || table_name_ident || ' ENABLE ROW LEVEL SECURITY';
        EXECUTE 'ALTER TABLE ' || table_name_ident || ' FORCE ROW LEVEL SECURITY';
        
        -- Create a policy that checks the company_id column
        -- Special handling for 'companies' table where the key is 'id'
        IF table_name_ident::text = 'public.companies' THEN
             EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || table_name_ident ||
                ' FOR ALL USING (id = public.get_company_id()) WITH CHECK (id = public.get_company_id())';
        ELSIF table_name_ident::text = 'public.purchase_order_line_items' THEN
             -- Special policy for child tables without a direct company_id
            EXECUTE 'CREATE POLICY "Allow all access via parent PO" ON ' || table_name_ident ||
                ' FOR ALL USING ((SELECT company_id FROM public.purchase_orders po WHERE po.id = purchase_order_id) = public.get_company_id())';
        ELSE
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON ' || table_name_ident ||
                ' FOR ALL USING (company_id = public.get_company_id()) WITH CHECK (company_id = public.get_company_id())';
        END IF;
    END LOOP;
END;
$$;

-- Execute the procedure to apply the policies
CALL apply_rls_policies();


-- =============================================
-- SECTION 10: TRIGGERS
-- =============================================

-- Safely drop existing trigger before creating
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Recreate trigger to call our new function
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update product full-text search vector
CREATE OR REPLACE FUNCTION update_product_fts_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    new.fts_document := to_tsvector('english', coalesce(new.title, '') || ' ' || coalesce(new.description, '') || ' ' || coalesce(new.product_type, ''));
    RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_product_fts ON public.products;
CREATE TRIGGER trg_update_product_fts
BEFORE INSERT OR UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION update_product_fts_document();

-- Trigger to update inventory ledger on stock change
CREATE OR REPLACE FUNCTION log_inventory_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_change_type TEXT;
BEGIN
    -- Determine change type from context if possible, otherwise 'manual_adjustment'
    BEGIN
        v_change_type := current_setting('app.change_type', true);
    EXCEPTION WHEN OTHERS THEN
        v_change_type := 'manual_adjustment';
    END;

    INSERT INTO public.inventory_ledger(company_id, variant_id, quantity_change, new_quantity, change_type, notes)
    VALUES (new.company_id, new.id, new.inventory_quantity - old.inventory_quantity, new.inventory_quantity, v_change_type, 'Stock level updated');
    RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_inventory_change ON public.product_variants;
CREATE TRIGGER trg_log_inventory_change
AFTER UPDATE OF inventory_quantity ON public.product_variants
FOR EACH ROW
WHEN (new.inventory_quantity <> old.inventory_quantity)
EXECUTE FUNCTION log_inventory_change();


-- Final check: Ensure RLS is enabled on the users table, as it's critical.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can only see themselves" ON public.users;
CREATE POLICY "Users can only see themselves" ON public.users
FOR SELECT USING (id = auth.uid());

    