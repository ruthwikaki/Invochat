-- =================================================================
-- INITIAL CLEANUP - Drop existing objects if they exist
-- =================================================================
-- Drop dependent triggers before functions
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.create_rls_policy(text);

-- Drop types
DROP TYPE IF EXISTS public.user_role;

-- =================================================================
-- EXTENSIONS - Ensure required extensions are enabled
-- =================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =================================================================
-- TYPES - Define custom types used in the application
-- =================================================================
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- =================================================================
-- HELPER FUNCTIONS
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT CASE
    WHEN nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '') IS NULL THEN NULL
    ELSE (nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', ''))::uuid
  END;
$$;


-- =================================================================
-- TABLES - Define the core database structure
-- =================================================================

-- Companies Table: Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Users Table: Stores app-specific user data, separate from auth.users
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);


-- Products Table: The parent for all product variants
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

-- Product Variants Table
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- Price in cents
    compare_at_price integer, -- In cents
    cost integer, -- In cents
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- In cents
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);

-- Customer Addresses Table
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping',
    first_name text,
    last_name text,
    company text,
    address1 text,
    address2 text,
    city text,
    province_code text,
    country_code text,
    zip text,
    phone text,
    is_default boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_customer_id ON public.customer_addresses(customer_id);

-- Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0, -- In cents
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL, -- In cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);


-- Discounts Table
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL,
    value integer NOT NULL, -- In cents for fixed_amount, basis points for percentage
    minimum_purchase integer,
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all',
    is_active boolean DEFAULT true,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_discounts_company_id ON public.discounts(company_id);


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  sync_status text,
  last_sync_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone
);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- ... and so on for all other tables you need.

-- =================================================================
-- NEW USER HANDLING - Trigger to create corresponding public records
-- =================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  company_id uuid;
  company_name text;
BEGIN
  -- Extract company_name from metadata, default if not present
  company_name := COALESCE(new.raw_app_meta_data ->> 'company_name', 'My Company');

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (company_name)
  RETURNING id INTO company_id;

  -- Create a corresponding public.users record
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
    COALESCE(raw_app_meta_data, '{}'::jsonb),
    '{company_id}',
    to_jsonb(company_id)
  )
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =================================================================
-- ROW LEVEL SECURITY (RLS)
-- =================================================================

-- Function to dynamically create RLS policies for tables with company_id
CREATE OR REPLACE FUNCTION create_rls_policy(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
    EXECUTE format('DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.%I;', table_name);
    EXECUTE format('CREATE POLICY "Users can only see their own company''s data." ON public.%I FOR ALL USING (company_id = public.get_current_company_id());', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all relevant tables
SELECT create_rls_policy(table_name)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'products', 'product_variants', 'orders', 'order_line_items',
    'customers', 'customer_addresses', 'discounts', 'integrations'
    -- Add other company-specific tables here as needed
  );

-- Specific RLS for the users table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can see other users in their own company" ON public.users;
CREATE POLICY "Users can see other users in their own company" ON public.users
    FOR SELECT USING (company_id = public.get_current_company_id());
DROP POLICY IF EXISTS "Owners can manage users in their company" ON public.users;
CREATE POLICY "Owners can manage users in their company" ON public.users
    FOR ALL USING (company_id = public.get_current_company_id() AND (SELECT role FROM public.users WHERE id = auth.uid()) = 'Owner');

-- Specific RLS for the companies table
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can only see their own company" ON public.companies;
CREATE POLICY "Users can only see their own company" ON public.companies
    FOR SELECT USING (id = public.get_current_company_id());

-- =================================================================
-- TRIGGERS - For automated updates
-- =================================================================

-- Function to update the 'updated_at' timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply the trigger to all tables with an 'updated_at' column
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_integrations_updated_at ON public.integrations;
CREATE TRIGGER update_integrations_updated_at BEFORE UPDATE ON public.integrations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- =================================================================
-- UNIQUE CONSTRAINTS
-- =================================================================
-- Drop existing constraints before adding new ones to make script re-runnable
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_order_number_per_company;
ALTER TABLE public.discounts DROP CONSTRAINT IF EXISTS unique_discount_code_per_company;
ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;

ALTER TABLE public.orders ADD CONSTRAINT unique_order_number_per_company UNIQUE (company_id, order_number);
ALTER TABLE public.discounts ADD CONSTRAINT unique_discount_code_per_company UNIQUE (company_id, code);
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);


-- =================================================================
-- GRANT PERMISSIONS
-- =================================================================
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;
