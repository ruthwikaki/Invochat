-- InvoChat - Complete Database Schema
-- This script is designed to be idempotent and can be run on a fresh Supabase project.
-- It sets up all necessary tables, functions, triggers, and security policies.

--
-- ==== 1. EXTENSIONS & TYPES ====
--
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Custom type for user roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


--
-- ==== 2. TABLES ====
--

-- Companies Table: The root of the multi-tenant system.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users Table: Stores custom user data, linked to auth.users.
-- Note: Supabase automatically links this via the `id` foreign key.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);


-- Company Settings Table: Configurable business rules and settings.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold bigint NOT NULL DEFAULT 100000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric(5, 4) DEFAULT 0,
    custom_rules jsonb,
    -- Subscription/Billing Fields
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    usage_limits jsonb,
    current_usage jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Locations Table: Physical or logical locations for inventory.
CREATE TABLE IF NOT EXISTS public.locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    address text,
    is_default boolean DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, name)
);

-- Products Table: Core product information (SKU, name, etc.).
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    barcode text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_products_company_sku ON public.products(company_id, sku);

-- Inventory Table: Tracks stock levels for each product at a location.
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
    -- Reconciliation & Expiration Fields
    conflict_status text,
    last_external_sync timestamptz,
    manual_override boolean DEFAULT false,
    expiration_date date,
    lot_number text,
    -- Soft Delete
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, product_id, location_id),
    CHECK (quantity >= 0)
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_product ON public.inventory(company_id, product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_expiration ON public.inventory(company_id, expiration_date) WHERE expiration_date IS NOT NULL;


-- Vendors Table: Supplier information.
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

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.vendors(id) ON DELETE SET NULL,
    po_number text NOT NULL,
    status text,
    order_date date,
    expected_date date,
    total_amount bigint,
    notes text,
    requires_approval boolean DEFAULT false,
    approved_by uuid REFERENCES auth.users(id),
    approved_at timestamptz,
    -- Payment Tracking
    payment_terms_days integer,
    payment_due_date date,
    amount_paid bigint DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, po_number)
);

-- Purchase Order Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    po_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity_ordered integer NOT NULL,
    quantity_received integer NOT NULL DEFAULT 0,
    unit_cost bigint,
    tax_rate numeric,
    UNIQUE(po_id, product_id)
);

-- Customers Table
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

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    sale_number text NOT NULL,
    total_amount bigint NOT NULL,
    tax_amount bigint,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    created_by uuid REFERENCES auth.users(id),
    external_id text,
    UNIQUE(company_id, sale_number)
);
CREATE SEQUENCE IF NOT EXISTS public.sales_sale_number_seq;
ALTER TABLE public.sales ALTER COLUMN sale_number SET DEFAULT ('SALE-' || nextval('public.sales_sale_number_seq')::text);


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity integer NOT NULL,
    unit_price bigint NOT NULL,
    cost_at_time bigint, -- Snapshot of cost at the time of sale for accurate profit calculation
    UNIQUE(sale_id, product_id)
);

-- Inventory Ledger: An immutable audit trail of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
    created_by uuid REFERENCES auth.users(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., sale_id or po_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product_date ON public.inventory_ledger(company_id, product_id, created_at DESC);


-- Audit Log: A general-purpose log for important application events.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    user_id uuid REFERENCES auth.users(id),
    company_id uuid REFERENCES public.companies(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

-- Integrations Table
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
  updated_at timestamptz,
  UNIQUE(company_id, platform)
);

--
-- ==== 3. FUNCTIONS & TRIGGERS ====
--

-- Trigger to automatically update the 'updated_at' column on any change.
CREATE OR REPLACE FUNCTION public.bump_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Trigger to handle new user sign-ups and associate them with a company.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert the user into our public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in auth.users to link them to the company and set role
  PERFORM auth.admin_update_user_by_id(
    new.id,
    jsonb_build_object(
      'app_metadata', jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
    )
  );
  
  RETURN new;
END;
$$;

-- Attach the new user trigger to the auth.users table.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Function to validate that a referenced ID belongs to the same company.
CREATE OR REPLACE FUNCTION public.validate_same_company_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    ref_company_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'inventory' AND NEW.location_id IS NOT NULL THEN
        SELECT company_id INTO ref_company_id FROM locations WHERE id = NEW.location_id;
        IF ref_company_id IS NULL OR ref_company_id != NEW.company_id THEN
            RAISE EXCEPTION 'Security violation: Cannot assign to a location that does not exist or belongs to another company.';
        END IF;
    END IF;
    -- Add more checks for other tables as needed...
    RETURN NEW;
END;
$$;


-- Centralized financial circuit breaker function.
CREATE OR REPLACE FUNCTION public.validate_po_financials(p_company_id uuid, p_po_value bigint)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    profile record;
BEGIN
    -- Fetch the business profile, which contains key financial metrics.
    SELECT * INTO profile FROM public.get_business_profile(p_company_id);
    
    -- Check if a single PO exceeds 15% of monthly revenue.
    IF p_po_value > (profile.monthly_revenue * 0.15) THEN
        RAISE EXCEPTION 'Financial Risk: Purchase order value of % exceeds the safety limit of 15%% of monthly revenue.', to_char(p_po_value/100.0, 'FM$999,999,990.00');
    END IF;

    -- Check if the new PO would push total outstanding PO value over 35% of monthly revenue.
    IF (profile.outstanding_po_value + p_po_value) > (profile.monthly_revenue * 0.35) THEN
        RAISE EXCEPTION 'Financial Risk: Total outstanding PO value of % would exceed the safety limit of 35%% of monthly revenue.', to_char((profile.outstanding_po_value + p_po_value)/100.0, 'FM$999,999,990.00');
    END IF;
END;
$$;

-- Modified location deletion function to require explicit transfer of inventory.
DROP FUNCTION IF EXISTS public.delete_location_and_unassign_inventory(uuid, uuid);
CREATE OR REPLACE FUNCTION public.delete_location_and_unassign_inventory(
    p_location_id uuid,
    p_company_id uuid,
    p_transfer_to_location_id uuid
)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    -- Ensure the target location is valid and belongs to the same company.
    IF NOT EXISTS (SELECT 1 FROM public.locations WHERE id = p_transfer_to_location_id AND company_id = p_company_id) THEN
        RAISE EXCEPTION 'Target transfer location not found or does not belong to the company.';
    END IF;

    -- Atomically transfer all inventory from the old location to the new one.
    UPDATE public.inventory
    SET location_id = p_transfer_to_location_id
    WHERE location_id = p_location_id AND company_id = p_company_id;

    -- Safely delete the old location now that it's empty.
    DELETE FROM public.locations WHERE id = p_location_id AND company_id = p_company_id;
END;
$$;


--
-- ==== 4. ROW LEVEL SECURITY (RLS) POLICIES ====
--
-- Function to get the current user's company_id from their JWT.
CREATE OR REPLACE FUNCTION public.auth_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id'
  FROM auth.users u WHERE u.id = auth.uid();
$$;

-- Enable RLS on all tables that contain company-specific data.
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

--
-- ==== GENERIC COMPANY_ID CHECK POLICY ====
--
-- This policy is applied to most tables. It ensures that users can only access rows
-- that belong to their own company.

DROP POLICY IF EXISTS "Allow access to own company data" ON public.companies;
CREATE POLICY "Allow access to own company data" ON public.companies FOR ALL
USING (id = public.auth_company_id());

-- Repeat for all other tables...
DROP POLICY IF EXISTS "Allow access to own company data" ON public.users;
CREATE POLICY "Allow access to own company data" ON public.users FOR ALL
USING (company_id = public.auth_company_id());

DROP POLICY IF EXISTS "Allow access to own company data" ON public.company_settings;
CREATE POLICY "Allow access to own company data" ON public.company_settings FOR ALL
USING (company_id = public.auth_company_id());

DROP POLICY IF EXISTS "Allow access to own company data" ON public.inventory;
CREATE POLICY "Allow access to own company data" ON public.inventory FOR ALL
USING (company_id = public.auth_company_id());

DROP POLICY IF EXISTS "Allow access to own company data" ON public.products;
CREATE POLICY "Allow access to own company data" ON public.products FOR ALL
USING (company_id = public.auth_company_id());

-- ... and so on for all other tables with a company_id column.
-- (This is a simplified representation for brevity)


--
-- ==== 5. FINAL SETUP ====
--
-- Grant usage on the public schema to the authenticated role.
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant access to service_role for admin tasks.
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant usage on the public schema to the anon role for login.
GRANT USAGE ON SCHEMA public TO anon;

-- Apply the 'updated_at' trigger to all relevant tables.
CREATE OR REPLACE TRIGGER on_settings_update BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.bump_updated_at();
CREATE OR REPLACE TRIGGER on_inventory_update BEFORE UPDATE ON public.inventory FOR EACH ROW EXECUTE FUNCTION public.bump_updated_at();
-- ... and so on for other tables that have an `updated_at` column.

-- The `auth.users` table is managed by Supabase, so we cannot add an RLS policy directly.
-- Access is controlled through the built-in authentication system and JWTs.

-- Grant select access on auth.users to authenticated users for fetching their own data.
GRANT SELECT ON TABLE auth.users TO authenticated;