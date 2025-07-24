
-- #################################################################
-- ### DATABASE MIGRATION SCRIPT (Inventory Enhancements)
-- ### This script applies targeted changes to the existing schema.
-- #################################################################

-- Enable UUID generation if it's not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END$$;


-- #################################################################
-- ### Table Alterations for Inventory Management Edge Cases
-- #################################################################

-- Add columns to product_variants if they don't exist
DO $$
BEGIN
    -- Add reorder_point for minimum stock level tracking
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='reorder_point') THEN
        ALTER TABLE public.product_variants ADD COLUMN reorder_point integer;
    END IF;

    -- Add reorder_quantity for defining order amounts
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='reorder_quantity') THEN
        ALTER TABLE public.product_variants ADD COLUMN reorder_quantity integer;
    END IF;
    
    -- Add supplier_id to link variants to suppliers for reordering
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='supplier_id') THEN
        ALTER TABLE public.product_variants ADD COLUMN supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL;
    END IF;

    -- Add reserved_quantity for tracking allocated stock
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='reserved_quantity') THEN
        ALTER TABLE public.product_variants ADD COLUMN reserved_quantity integer NOT NULL DEFAULT 0;
    END IF;

    -- Add in_transit_quantity for tracking incoming stock
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='in_transit_quantity') THEN
        ALTER TABLE public.product_variants ADD COLUMN in_transit_quantity integer NOT NULL DEFAULT 0;
    END IF;
    
    -- Add quality_status for damaged/returned stock
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='product_variants' AND column_name='quality_status') THEN
        ALTER TABLE public.product_variants ADD COLUMN quality_status text NOT NULL DEFAULT 'available';
        
        -- Add a check constraint for the new column
        ALTER TABLE public.product_variants ADD CONSTRAINT check_quality_status
            CHECK (quality_status IN ('available', 'damaged', 'returned', 'quarantine'));
    END IF;
END$$;

-- Add check constraint to prevent negative inventory
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'check_inventory_quantity_non_negative' AND conrelid = 'public.product_variants'::regclass
    ) THEN
        ALTER TABLE public.product_variants 
        ADD CONSTRAINT check_inventory_quantity_non_negative
        CHECK (inventory_quantity >= 0);
    END IF;
END$$;


-- #################################################################
-- ### Idempotent Table and Index Creation (for completeness)
-- ### This ensures the base schema exists before altering it.
-- #################################################################

-- Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    owner_id uuid NOT NULL REFERENCES auth.users(id)
);

-- Users Table (public schema) - Simplified, as auth.users is the source of truth
CREATE TABLE IF NOT EXISTS public.company_users (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.company_role NOT NULL DEFAULT 'Member',
    PRIMARY KEY (user_id, company_id)
);

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Products Table
CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS products_company_id_idx ON public.products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS products_external_id_company_id_unique ON public.products(company_id, external_product_id) WHERE external_product_id IS NOT NULL;

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
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
    updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS variants_product_id_idx ON public.product_variants(product_id);
CREATE UNIQUE INDEX IF NOT EXISTS variants_sku_company_id_unique ON public.product_variants(sku, company_id);
CREATE UNIQUE INDEX IF NOT EXISTS variants_ext_id_company_id_unique ON public.product_variants(external_variant_id, company_id) WHERE external_variant_id IS NOT NULL;


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    external_customer_id text,
    name text,
    email text,
    phone text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    deleted_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS customers_ext_id_company_id_unique ON public.customers(external_customer_id, company_id) WHERE external_customer_id IS NOT NULL;

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz
);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL,
    expected_arrival_date date,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    idempotency_key uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS po_number_company_id_unique ON public.purchase_orders(po_number, company_id);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL
);

-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_platform_company_id_unique ON public.integrations(platform, company_id);

-- Webhook Events Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS webhook_events_unique_id ON public.webhook_events(integration_id, webhook_id);

-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS inventory_ledger_variant_id_idx ON public.inventory_ledger(variant_id);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role public.message_role NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean DEFAULT false,
    created_at timestamptz DEFAULT now()
);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier real NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    fixed_fee INTEGER, -- in cents
    percentage_fee NUMERIC,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- Imports Table
CREATE TABLE IF NOT EXISTS public.imports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    import_type TEXT NOT NULL,
    file_name TEXT NOT NULL,
    total_rows INT,
    processed_rows INT,
    failed_rows INT,
    status TEXT NOT NULL DEFAULT 'pending',
    errors JSONB,
    summary JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- #################################################################
-- ### Functions & Triggers
-- #################################################################

-- Drop dependent policies first
DROP POLICY IF EXISTS "User can see other users in their company" ON public.company_users;
DROP POLICY IF EXISTS "User can access their own company data" ON public.products;
DROP POLICY IF EXISTS "User can access their own company data" ON public.product_variants;
DROP POLICY IF EXISTS "User can access their own company data" ON public.orders;
DROP POLICY IF EXISTS "User can access their own company data" ON public.order_line_items;
DROP POLICY IF EXISTS "User can access their own company data" ON public.customers;
DROP POLICY IF EXISTS "User can access their own company data" ON public.suppliers;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_orders;
DROP POLICY IF EXISTS "User can access their own company data" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "User can access their own company data" ON public.integrations;
DROP POLICY IF EXISTS "User can access their own company data" ON public.webhook_events;
DROP POLICY IF EXISTS "User can access their own company data" ON public.inventory_ledger;
DROP POLICY IF EXISTS "User can access their own company data" ON public.conversations;
DROP POLICY IF EXISTS "User can access their own company data" ON public.messages;
DROP POLICY IF EXISTS "User can access their own company data" ON public.audit_log;
DROP POLICY IF EXISTS "User can access their own company settings" ON public.company_settings;
DROP POLICY IF EXISTS "User can access their own company data" ON public.channel_fees;

-- Drop the trigger to avoid dependency errors on the function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_company_id_for_user(p_user_id uuid);
DROP FUNCTION IF EXISTS public.check_user_permission(p_user_id uuid, p_required_role text);
DROP FUNCTION IF EXISTS public.lock_user_account(p_user_id uuid, p_lockout_duration text);


-- Function to create a new company for a new user and link them.
CREATE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company and get its ID
  INSERT INTO public.companies (name, owner_id)
  VALUES (new.raw_user_meta_data->>'company_name', new.id)
  RETURNING id INTO new_company_id;

  -- Add the new user to the company_users table
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  -- Update the user's app_metadata with the company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to call the function when a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Function to get company_id for a user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid AS $$
BEGIN
  RETURN (
    SELECT company_id
    FROM public.company_users
    WHERE user_id = p_user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role public.company_role)
RETURNS boolean AS $$
DECLARE
    user_role public.company_role;
BEGIN
    SELECT role INTO user_role FROM public.company_users WHERE user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Owner' AND user_role = 'Owner' THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Admin' AND (user_role = 'Owner' OR user_role = 'Admin') THEN
        RETURN TRUE;
    ELSIF p_required_role = 'Member' AND (user_role IN ('Owner', 'Admin', 'Member')) THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to lock a user account
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void AS $$
BEGIN
  UPDATE auth.users
  SET banned_until = now() + p_lockout_duration::interval
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- #################################################################
-- ### Row-Level Security (RLS)
-- #################################################################

-- Enable RLS on all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "User can access their own company data" ON public.products FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.product_variants FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.purchase_orders FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.purchase_order_line_items FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_company_id_for_user(auth.uid())));
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own conversation data" ON public.conversations FOR ALL USING (user_id = auth.uid());
CREATE POLICY "User can access their own company data" ON public.messages FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.audit_log FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company settings" ON public.company_settings FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can see other users in their company" ON public.company_users FOR SELECT USING (company_id = public.get_company_id_for_user(auth.uid()));
CREATE POLICY "User can access their own company data" ON public.channel_fees FOR ALL USING (company_id = public.get_company_id_for_user(auth.uid()));
