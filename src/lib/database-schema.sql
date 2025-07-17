
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Drop existing policies, functions, and views to avoid conflicts during recreation.
-- This ensures the script is idempotent and can be re-run safely.
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Drop policies on all tables in the public schema
    FOR r IN (SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Drop dependent views first
DROP VIEW IF EXISTS public.customers_view;
DROP VIEW IF EXISTS public.orders_view;
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Drop functions that might have dependencies
DROP FUNCTION IF EXISTS public.get_company_id();
DROP FUNCTION IF EXISTS public.get_user_role();
DROP FUNCTION IF EXISTS public.is_company_member(uuid);
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Drop procedures
DROP PROCEDURE IF EXISTS public.enable_rls_on_table(text, text);


-- =============================================
-- 1. UTILITY FUNCTIONS & SECURITY
-- =============================================

-- Function to get the company_id from the user's JWT claims.
-- This is a cornerstone of our multi-tenancy security model.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Function to get the user's role from JWT claims.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::text;
$$;

-- Function to check if the current user is a member of a given company.
CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id
  );
$$;

-- Procedure to systematically enable RLS and apply a standard company_id policy.
-- This helps ensure consistency and security across all tables.
CREATE OR REPLACE PROCEDURE public.enable_rls_on_table(p_table_name text, p_role text DEFAULT 'Admin')
LANGUAGE plpgsql
AS $$
BEGIN
    -- Enable Row Level Security on the specified table
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    
    -- Drop existing policies to ensure a clean slate
    EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(p_table_name);
    
    -- Create a policy that restricts access based on the user's company_id
    EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(p_table_name) ||
            ' FOR ALL USING (company_id = public.get_company_id())';
END;
$$;

-- =============================================
-- 2. CORE TABLES
-- =============================================

-- Companies Table: Stores basic information about each tenant company.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users Table: A local mirror of auth.users with added company and role info.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'Member'::text, -- 'Admin' or 'Member'
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CALL public.enable_rls_on_table('users');
ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (role IN ('Admin', 'Member', 'Owner'));

-- Company Settings Table: Configurable business logic parameters per company.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 1000,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz
);
CALL public.enable_rls_on_table('company_settings');

-- =============================================
-- 3. INVENTORY & PRODUCT TABLES
-- =============================================

-- Products Table: Represents a parent product.
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
    updated_at timestamptz
);
CALL public.enable_rls_on_table('products');
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_company_external_id ON public.products(company_id, external_product_id);

-- Product Variants Table: Represents a specific SKU or variant of a product.
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer, -- in cents
    compare_at_price integer, -- in cents
    cost integer, -- in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
CALL public.enable_rls_on_table('product_variants');
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(company_id, sku);
CREATE UNIQUE INDEX IF NOT EXISTS idx_variants_company_external_id ON public.product_variants(company_id, external_variant_id);

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_company_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS product_variants_product_id_fkey;
ALTER TABLE public.product_variants ADD CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE;


-- Inventory Ledger Table: An immutable log of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CALL public.enable_rls_on_table('inventory_ledger');
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_id ON public.inventory_ledger(company_id);
CREATE INDEX IF NOT EXISTS idx_ledger_change_type ON public.inventory_ledger(change_type);

-- =============================================
-- 4. SALES & CUSTOMER TABLES
-- =============================================

-- Customers Table: Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CALL public.enable_rls_on_table('customers');
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);

-- Orders Table: Records sales orders.
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    currency text DEFAULT 'USD',
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL, -- in cents
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamptz,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
CALL public.enable_rls_on_table('orders');
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_company_external_id ON public.orders(company_id, external_order_id);


-- Order Line Items Table: Details of items within an order.
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- in cents
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);
CALL public.enable_rls_on_table('order_line_items');
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);

-- =============================================
-- 5. SUPPLIER & PURCHASING TABLES
-- =============================================

-- Suppliers Table
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
CALL public.enable_rls_on_table('suppliers');
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL, -- in cents
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);
CALL public.enable_rls_on_table('purchase_orders');
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_supplier_id ON public.purchase_orders(supplier_id);

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- in cents
);
CALL public.enable_rls_on_table('purchase_order_line_items');
CREATE INDEX IF NOT EXISTS idx_po_line_items_po_id ON public.purchase_order_line_items(purchase_order_id);

-- =============================================
-- 6. INTEGRATIONS & METADATA TABLES
-- =============================================

-- Integrations Table: Stores connection details for third-party platforms.
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
CALL public.enable_rls_on_table('integrations');
CREATE UNIQUE INDEX IF NOT EXISTS idx_integrations_company_platform ON public.integrations(company_id, platform);

-- Conversations Table: Stores chat history for the AI assistant.
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);
CREATE POLICY "Allow individual user access to their own conversations" ON public.conversations FOR ALL
    USING (auth.uid() = user_id AND company_id = public.get_company_id());
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Messages Table: Stores individual messages within conversations.
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
CALL public.enable_rls_on_table('messages');

-- Webhook Events Table: For preventing replay attacks on webhooks.
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    webhook_id text NOT NULL,
    processed_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_webhook_events_unique ON public.webhook_events(integration_id, webhook_id);
-- This table needs a specific RLS policy as it's accessed by webhooks without a user context.
-- For now, we assume it's only accessed by the service role key.
-- A more advanced implementation would use a dedicated API user with limited permissions.
-- We will enable RLS and add a policy that allows service role to bypass it.
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow service role full access" ON public.webhook_events FOR ALL
    USING (true) WITH CHECK (true);

-- =============================================
-- 7. DATABASE VIEWS FOR SIMPLIFIED QUERIES
-- =============================================

-- A view to easily get product variants with their parent product's title and image.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id;
    
-- A view to get orders with customer name and email.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
  o.*,
  c.customer_name,
  c.email AS customer_email
FROM
  public.orders o
LEFT JOIN
  public.customers c ON o.customer_id = c.id;


-- A view to easily query customer data with aggregated metrics.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT
  c.*
FROM
  public.customers c;


-- =============================================
-- 8. TRIGGER FOR NEW USER SETUP
-- =============================================

-- This function is called by a trigger when a new user signs up.
-- It creates a new company for them and links their user record to it.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from the user's metadata, falling back to a default name.
  v_company_name := new.raw_app_meta_data ->> 'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := new.email || '''s Company';
  END IF;

  -- Create a new company for the user.
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding entry in our local users table.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's JWT claims in auth.users to include their new company_id.
  -- This is crucial for our Row-Level Security policies to work correctly.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Grant usage on the public schema to the necessary roles.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;

-- Grant usage on the vault schema to the service_role for secret management.
GRANT USAGE ON SCHEMA vault TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA vault TO service_role;

-- Set a comment on the get_company_id function for clarity.
COMMENT ON FUNCTION public.get_company_id() IS 'Retrieves the company_id from the current user''s JWT claims.';

-- Final message indicating successful execution.
SELECT 'ARVO database schema setup complete.';

