--
-- InvoChat - Comprehensive Database Schema
--
-- This script is designed to be idempotent and can be run safely multiple times.
-- It creates all necessary tables, types, functions, and row-level security policies
-- for the application to function correctly.
--

-- 1. EXTENSIONS
-- Required for UUID generation
create extension if not exists "uuid-ossp" with schema "extensions";


-- 2. CUSTOM TYPES
-- We create custom types for things like roles and statuses to enforce consistency.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('Draft', 'Ordered', 'Partially Received', 'Received', 'Cancelled');
    END IF;
END$$;


-- 3. HELPER FUNCTIONS
-- These functions are used throughout the schema, especially in RLS policies.

-- Gets the company ID of the currently authenticated user.
-- This is the cornerstone of our multi-tenant security model.
DROP FUNCTION IF EXISTS public.get_company_id() CASCADE;
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    SELECT current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id'
    INTO company_id_val;
    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE;

-- Checks if a user has the required role within their company.
-- Throws an error if the user does not have permission.
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id UUID, p_required_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_role_val TEXT;
BEGIN
    -- Get the user's role from the users table
    SELECT role INTO user_role_val FROM public.users WHERE id = p_user_id AND company_id = public.get_company_id();

    IF user_role_val IS NULL THEN
        -- User does not exist or does not belong to the company
        RETURN FALSE;
    END IF;

    -- Check if the user's role meets the required role
    -- This assumes a hierarchy: Owner > Admin > Member
    IF p_required_role = 'Admin' AND user_role_val IN ('Owner', 'Admin') THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Owner' AND user_role_val = 'Owner' THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE;


-- 4. TABLES
-- Core table definitions.

CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email TEXT,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    predictive_stock_days INT NOT NULL DEFAULT 7,
    currency TEXT DEFAULT 'USD',
    timezone TEXT DEFAULT 'UTC',
    tax_rate NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT,
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT,
    deleted_at TIMESTAMPTZ, -- For soft deletes
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    title TEXT,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    barcode TEXT,
    price INT, -- in cents
    compare_at_price INT, -- in cents
    cost INT, -- in cents
    inventory_quantity INT NOT NULL DEFAULT 0,
    location TEXT,
    external_variant_id TEXT,
    deleted_at TIMESTAMPTZ, -- For soft deletes
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID, -- Can be null for guest checkouts
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    cost_at_time INT,
    external_line_item_id TEXT
);

CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0,
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    address_type TEXT NOT NULL DEFAULT 'shipping', -- e.g., 'shipping', 'billing'
    first_name TEXT,
    last_name TEXT,
    company TEXT,
    address1 TEXT,
    address2 TEXT,
    city TEXT,
    province_code TEXT,
    country_code TEXT,
    zip TEXT,
    phone TEXT,
    is_default BOOLEAN DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status public.po_status NOT NULL DEFAULT 'Draft',
    po_number TEXT NOT NULL,
    total_cost INT NOT NULL,
    expected_arrival_date DATE,
    idempotency_key UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE RESTRICT,
    quantity INT NOT NULL,
    cost INT NOT NULL -- Cost per unit in cents
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    shop_domain TEXT,
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMPTZ,
    sync_status TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    last_accessed_at TIMESTAMPTZ DEFAULT now(),
    is_starred BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    component TEXT,
    component_props JSONB,
    visualization JSONB,
    confidence NUMERIC,
    assumptions TEXT[],
    is_error BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID REFERENCES public.companies(id) ON DELETE SET NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee NUMERIC NOT NULL, -- in cents
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.webhook_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id TEXT NOT NULL,
    processed_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);

CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- 5. INDEXES
-- Indexes for performance on frequently queried columns.

CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger(company_id);


-- 6. VIEWS
-- Views to simplify complex queries and for use in analytics.

-- NOTE: The view is created with SECURITY INVOKER to ensure RLS policies of the
-- querying user are applied, not the policies of the view creator.
CREATE OR REPLACE VIEW public.product_variants_with_details
WITH (security_invoker=true)
AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE p.deleted_at IS NULL AND pv.deleted_at IS NULL;


-- 7. ROW-LEVEL SECURITY (RLS)
-- This is the core of the multi-tenant security model.

-- Function to enable RLS on all tables in the public schema
CREATE OR REPLACE PROCEDURE enable_rls_for_all_tables(schema_name TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN
        SELECT tablename FROM pg_tables WHERE schemaname = schema_name
    LOOP
        -- Enable RLS for each table
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name, table_record.tablename);
        
        -- Drop existing policy to ensure idempotency
        EXECUTE format('DROP POLICY IF EXISTS "Allow all access to own company data" ON %I.%I', schema_name, table_record.tablename);

        -- Create a generic policy for tables with a `company_id` column
        IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = schema_name
            AND table_name = table_record.tablename
            AND column_name = 'company_id'
        ) THEN
            EXECUTE format(
                'CREATE POLICY "Allow all access to own company data" ON %I.%I FOR ALL USING (company_id = public.get_company_id());',
                schema_name, table_record.tablename
            );
        -- Special policy for the `users` table
        ELSIF table_record.tablename = 'users' THEN
             EXECUTE format(
                'CREATE POLICY "Allow all access to own company data" ON %I.%I FOR ALL USING (id = auth.uid() AND company_id = public.get_company_id());',
                schema_name, table_record.tablename
            );
        -- Special policy for `customer_addresses` which links through `customers`
        ELSIF table_record.tablename = 'customer_addresses' THEN
             EXECUTE format(
                'CREATE POLICY "Allow all access to own company data" ON %I.%I FOR ALL USING (customer_id IN (SELECT id FROM public.customers WHERE company_id = public.get_company_id()));',
                schema_name, table_record.tablename
            );
        END IF;
    END LOOP;
END;
$$;

-- Execute the procedure to apply RLS policies
CALL enable_rls_for_all_tables('public');


-- 8. TRIGGERS
-- Database triggers for automatic actions.

-- Trigger function to create a company and user profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    new_company_id UUID;
    user_role public.user_role;
BEGIN
    -- 1. Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (new.raw_app_meta_data->>'company_name')
    RETURNING id INTO new_company_id;

    -- The first user to sign up for a company is the Owner
    user_role := 'Owner';

    -- 2. Create an entry in our public.users table
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, user_role);

    -- 3. Update the user's app_metadata with the new company_id and role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', user_role)
    WHERE id = new.id;

    RETURN new;
END;
$$;

-- Drop the trigger if it exists to ensure idempotency
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Create the trigger to fire after a new user is inserted into auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  -- We only want this to fire for new signups, not for invites
  WHEN (new.raw_app_meta_data->>'company_id' IS NULL)
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update inventory levels after a sale is recorded
CREATE OR REPLACE FUNCTION public.update_inventory_on_sale()
RETURNS TRIGGER AS $$
BEGIN
    -- Decrease inventory for the variant sold
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - NEW.quantity
    WHERE id = NEW.variant_id AND company_id = NEW.company_id;

    -- Create an entry in the inventory ledger
    INSERT INTO public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    SELECT
        NEW.company_id,
        NEW.variant_id,
        'sale',
        -NEW.quantity,
        pv.inventory_quantity, -- The new quantity after the update
        NEW.order_id,
        'Order #' || o.order_number
    FROM public.product_variants pv
    JOIN public.orders o ON o.id = NEW.order_id
    WHERE pv.id = NEW.variant_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS after_order_line_item_insert ON public.order_line_items;

CREATE TRIGGER after_order_line_item_insert
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_inventory_on_sale();


RAISE NOTICE 'InvoChat database schema setup complete.';
