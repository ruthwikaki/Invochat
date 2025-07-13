-- InvoChat SaaS Schema
-- Version: 1.0
-- Description: This script sets up the full database schema for the multi-tenant
-- inventory management application. It is designed to be idempotent and can be
-- run multiple times without causing errors.

-- ----------------------------------------
-- 1. PRE-CONFIGURATION & EXTENSIONS
-- ----------------------------------------

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------
-- 2. CLEANUP OLD/DEPRECATED OBJECTS
-- ----------------------------------------

-- Drop old tables if they exist to avoid conflicts.
-- The `CASCADE` option removes dependent objects like policies and triggers.
DROP TABLE IF EXISTS public.inventory CASCADE;
DROP TABLE IF EXISTS public.inventory_ledger CASCADE;
DROP TABLE IF EXISTS public.sales CASCADE;
DROP TABLE IF EXISTS public.sale_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.company_dashboard_metrics CASCADE;

-- Drop old functions if they exist
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_sales_velocity(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);


-- ----------------------------------------
-- 3. HELPER FUNCTIONS
-- ----------------------------------------

-- Function to get the current user's ID
CREATE OR REPLACE FUNCTION public.get_current_user_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid;
$$;

-- Function to get the company_id from the user's metadata
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT CASE
    WHEN nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id' IS NOT NULL
    THEN (nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id')::uuid
    ELSE NULL
  END;
$$;

-- Trigger function to automatically update `updated_at` columns
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------
-- 4. CORE TABLE CREATION
-- ----------------------------------------

-- Companies table to support multi-tenancy
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Users table, linking auth users to companies
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email text,
  role user_role NOT NULL DEFAULT 'Member'::user_role,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

-- Company-specific settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);

-- Products table (parent for variants)
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text, -- e.g., 'active', 'draft', 'archived'
    image_url text,
    external_product_id text, -- ID from the source platform
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_company_id_external_product_id_key;
ALTER TABLE public.products ADD CONSTRAINT products_company_id_external_product_id_key UNIQUE (company_id, external_product_id);

-- Product Variants table (the actual sellable items with SKUs)
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text,
    title text, -- e.g., 'Small' or 'Red'
    option1_name text, option1_value text,
    option2_name text, option2_value text,
    option3_name text, option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer,
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_sku_key;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_sku_key UNIQUE (company_id, sku);

-- Inventory Ledger for immutable stock movement records
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'return', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_company_id_email_key;
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email);


-- Customer Addresses table
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping', -- 'shipping' or 'billing'
    first_name text, last_name text,
    company text,
    address1 text, address2 text,
    city text, province_code text, country_code text, zip text,
    phone text,
    is_default boolean DEFAULT false
);

-- Orders table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id),
    financial_status text, -- e.g., 'paid', 'pending', 'refunded'
    fulfillment_status text, -- e.g., 'fulfilled', 'unfulfilled', 'partial'
    currency text,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text, -- e.g., 'shopify', 'woocommerce'
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- Order Line Items table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id),
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- Price per unit in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- The cost of the item when it was sold
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Refunds table
CREATE TABLE IF NOT EXISTS public.refunds (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    refund_number text NOT NULL,
    status text NOT NULL DEFAULT 'pending', -- 'pending', 'completed', 'failed'
    reason text,
    note text,
    total_amount integer NOT NULL,
    created_by_user_id uuid REFERENCES public.users(id),
    external_refund_id text,
    created_at timestamptz DEFAULT now()
);

-- Refund Line Items table
CREATE TABLE IF NOT EXISTS public.refund_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    refund_id uuid NOT NULL REFERENCES public.refunds(id) ON DELETE CASCADE,
    order_line_item_id uuid NOT NULL REFERENCES public.order_line_items(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    amount integer NOT NULL, -- Total refund amount for these items in cents
    restock boolean DEFAULT true
);

-- Discounts table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- 'percentage', 'fixed_amount'
    value integer NOT NULL, -- in cents for fixed_amount, basis points for percentage
    minimum_purchase integer, -- in cents
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all', -- 'all', 'product', 'category'
    starts_at timestamptz,
    ends_at timestamptz,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- Suppliers table
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

-- Integrations table
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
ALTER TABLE public.integrations DROP CONSTRAINT IF EXISTS integrations_company_id_platform_key;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform);

-- Table for webhook de-duplication
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  platform text NOT NULL,
  external_webhook_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.webhook_events DROP CONSTRAINT IF EXISTS webhook_events_integration_id_external_webhook_id_key;
ALTER TABLE public.webhook_events ADD CONSTRAINT webhook_events_integration_id_external_webhook_id_key UNIQUE(integration_id, external_webhook_id);


-- ----------------------------------------
-- 5. NEW USER & COMPANY SETUP
-- ----------------------------------------

-- Function to create a new company and user profile when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Create a new company
  company_name := NEW.raw_app_meta_data->>'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    user_email := NEW.email;
    company_name := split_part(user_email, '@', 1) || '''s Store';
  END IF;

  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- Create a new user profile linked to the new company
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Trigger to call the function on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- ----------------------------------------
-- 6. ROW-LEVEL SECURITY (RLS)
-- ----------------------------------------

-- Enable RLS on all company-specific tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refund_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to ensure idempotency
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.companies;
DROP POLICY IF EXISTS "Users can only see users in their own company." ON public.users;
DROP POLICY IF EXISTS "Users can only see their own company's settings." ON public.company_settings;
DROP POLICY IF EXISTS "Users can only see their own company's products." ON public.products;
DROP POLICY IF EXISTS "Users can only see their own company's product variants." ON public.product_variants;
DROP POLICY IF EXISTS "Users can only see their own inventory ledger." ON public.inventory_ledger;
DROP POLICY IF EXISTS "Users can only see their own company's customers." ON public.customers;
DROP POLICY IF EXISTS "Users can only see their own company's addresses." ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can only see their own company's orders." ON public.orders;
DROP POLICY IF EXISTS "Users can only see their own company's line items." ON public.order_line_items;
DROP POLICY IF EXISTS "Users can only see their own company's refunds." ON public.refunds;
DROP POLICY IF EXISTS "Users can only see their own company's refund items." ON public.refund_line_items;
DROP POLICY IF EXISTS "Users can only see their own company's discounts." ON public.discounts;
DROP POLICY IF EXISTS "Users can only see their own company's suppliers." ON public.suppliers;
DROP POLICY IF EXISTS "Users can only see their own company's integrations." ON public.integrations;
DROP POLICY IF EXISTS "Users can only see their own company's webhook events." ON public.webhook_events;


-- Create RLS policies
CREATE POLICY "Users can only see their own company's data." ON public.companies FOR ALL USING (id = get_current_company_id());
CREATE POLICY "Users can only see users in their own company." ON public.users FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's settings." ON public.company_settings FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's products." ON public.products FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's product variants." ON public.product_variants FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own inventory ledger." ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's customers." ON public.customers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's addresses." ON public.customer_addresses FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's orders." ON public.orders FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's line items." ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's refunds." ON public.refunds FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's refund items." ON public.refund_line_items FOR ALL USING (company_id IN (SELECT company_id FROM refunds WHERE id = refund_line_items.refund_id));
CREATE POLICY "Users can only see their own company's discounts." ON public.discounts FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's suppliers." ON public.suppliers FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's integrations." ON public.integrations FOR ALL USING (company_id = get_current_company_id());
CREATE POLICY "Users can only see their own company's webhook events." ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM integrations WHERE company_id = get_current_company_id()));


-- ----------------------------------------
-- 7. TRIGGERS
-- ----------------------------------------

-- Drop existing triggers to ensure idempotency
DROP TRIGGER IF EXISTS update_company_settings_updated_at ON public.company_settings;
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
DROP TRIGGER IF EXISTS update_integrations_updated_at ON public.integrations;

-- Create triggers to update `updated_at` timestamps
CREATE TRIGGER update_company_settings_updated_at BEFORE UPDATE ON public.company_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


-- ----------------------------------------
-- 8. VIEWS & RPC FUNCTIONS (for analytics)
-- ----------------------------------------
-- Placeholder for future performance views and RPC functions.
-- Example:
-- CREATE OR REPLACE VIEW public.dashboard_metrics AS ...
-- CREATE OR REPLACE FUNCTION public.get_sales_analytics(p_company_id uuid) ...
-- The logic for these will be added as the features are built out.

-- Final script message
SELECT 'InvoChat SaaS schema setup script completed successfully.' as status;
