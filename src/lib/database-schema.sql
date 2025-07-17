-- InvoChat Database Schema
-- Version: 1.5.0
-- Description: Complete schema including tables, functions, RLS, and initial data.

-- This script is designed to be idempotent. It can be run multiple times without causing errors.
-- For new setups, run this entire script.
-- For existing setups, use the migration scripts provided.

--
-- Extensions
--
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA extensions;

--
-- Helper Functions
--

-- Function to safely get the current user's company_id from their JWT claims.
-- This is the cornerstone of the multi-tenant security model.
CREATE OR REPLACE FUNCTION public.get_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;
COMMENT ON FUNCTION public.get_company_id() IS 'Safely retrieves the company_id from the current user''s JWT claims.';

-- Function to safely get the current user's role from their JWT claims.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb ->> 'user_role', '');
$$;
COMMENT ON FUNCTION public.get_user_role() IS 'Safely retrieves the user''s role from their JWT claims.';


--
-- Table Definitions
--

-- Companies Table: Stores basic information about each company tenant.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores information about each company tenant.';

-- Users Table: Stores public-facing user data, linking users to companies.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role text DEFAULT 'member'::text,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Public user profiles, linking auth.users to a company.';

-- Company Settings Table: Tenant-specific configuration for business logic.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000, -- Stored in cents
    predictive_stock_days integer NOT NULL DEFAULT 7,
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
COMMENT ON TABLE public.company_settings IS 'Tenant-specific settings for AI and business logic.';

-- Products Table: Core product information.
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
    updated_at timestamptz,
    deleted_at timestamptz,
    fts_document tsvector GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || coalesce(description, ''))) STORED
);
COMMENT ON TABLE public.products IS 'Core product information, synced from external platforms.';

-- Product Variants Table: Specific versions of a product (e.g., size, color).
CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
    price integer, -- Price in cents
    compare_at_price integer, -- In cents
    cost integer, -- Cost in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    external_variant_id text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE(company_id, sku)
);
COMMENT ON TABLE public.product_variants IS 'Specific variations of a product, including SKU and inventory levels.';

-- Inventory Ledger Table: Records all stock movements for auditing.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'sale', 'purchase_order', 'manual_adjustment', 'reconciliation'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- Can link to an order_id, purchase_order_id, etc.
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.inventory_ledger IS 'Append-only log of all inventory changes for auditing.';


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent integer DEFAULT 0, -- In cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);
COMMENT ON TABLE public.customers IS 'Stores customer information, aggregated from sales data.';

-- Orders Table
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
    UNIQUE(company_id, external_order_id, source_platform)
);
COMMENT ON TABLE public.orders IS 'Stores sales order information synced from platforms.';

-- Order Line Items Table
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE SET NULL,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE SET NULL,
    product_name text NOT NULL,
    variant_title text,
    sku text NOT NULL,
    quantity integer NOT NULL,
    price integer NOT NULL, -- in cents
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer, -- cost of goods in cents at the time of sale
    fulfillment_status text DEFAULT 'unfulfilled',
    requires_shipping boolean DEFAULT true,
    external_line_item_id text
);
COMMENT ON TABLE public.order_line_items IS 'Individual items within a sales order.';

-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.suppliers IS 'Stores information about product suppliers/vendors.';

-- Purchase Orders Table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    status text NOT NULL DEFAULT 'Draft',
    po_number text NOT NULL,
    total_cost integer NOT NULL, -- in cents
    expected_arrival_date date,
    idempotency_key uuid,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.purchase_orders IS 'Records for orders placed with suppliers.';

-- Purchase Order Line Items Table
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    purchase_order_id uuid NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    quantity integer NOT NULL,
    cost integer NOT NULL -- cost per unit in cents
);
COMMENT ON TABLE public.purchase_order_line_items IS 'Individual items within a purchase order.';


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
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
COMMENT ON TABLE public.integrations IS 'Stores details of connected e-commerce platforms.';

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
COMMENT ON TABLE public.conversations IS 'Stores chat conversation history.';

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT uuid_generate_v4() PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    role text NOT NULL, -- 'user' or 'assistant'
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.messages IS 'Individual messages within a chat conversation.';


--
-- Indexes for Performance
--
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_change_type ON public.inventory_ledger(change_type);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier_id ON public.purchase_orders(supplier_id);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);
CREATE INDEX IF NOT EXISTS fts_product_search_idx ON public.products USING GIN (fts_document);
CREATE INDEX IF NOT EXISTS idx_orders_company_created_status ON orders(company_id, created_at DESC, fulfillment_status);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_order ON order_line_items(variant_id, order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_variant_created ON inventory_ledger(variant_id, created_at DESC);


--
-- Views
--

-- A view to unify products and their variants for easier querying.
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
WHERE p.deleted_at IS NULL AND pv.deleted_at IS NULL;
COMMENT ON VIEW public.product_variants_with_details IS 'Denormalized view joining products and variants for easy access to product details.';

-- A view to easily see aggregated customer data.
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.created_at,
    COALESCE(o.total_orders, 0) as total_orders,
    COALESCE(o.total_spent, 0) as total_spent,
    o.first_order_date
FROM public.customers c
LEFT JOIN (
    SELECT
        customer_id,
        count(*) as total_orders,
        sum(total_amount) as total_spent,
        min(created_at) as first_order_date
    FROM public.orders
    GROUP BY customer_id
) o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL;
COMMENT ON VIEW public.customers_view IS 'Aggregates customer order data for easy querying.';

-- A view to get order details including customer info.
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.customer_name,
    c.email as customer_email
FROM
    public.orders o
LEFT JOIN
    public.customers c ON o.customer_id = c.id;
COMMENT ON VIEW public.orders_view IS 'Denormalized view joining orders with customer details.';

--
-- Stored Procedures and Functions
--

-- Function to handle new user creation.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER -- This function must run with the permissions of the user who created it (the database owner)
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from the user's metadata, falling back to a default name.
  v_company_name := new.raw_app_meta_data->>'company_name';
  if v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := new.email || '''s Company';
  END IF;

  -- Create a new company for the new user.
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Create a corresponding entry in the public.users table.
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, v_company_id, new.email, 'Owner');

  -- Update the user's app_metadata in the auth.users table with the new company_id and role.
  -- This makes the company_id and role available in the user's JWT for RLS.
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'user_role', 'Owner')
  WHERE id = new.id;
  
  -- Create default settings for the new company.
  INSERT INTO public.company_settings(company_id) VALUES (v_company_id);

  RETURN new;
END;
$$;
COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger function to create a new company and user profile upon user signup.';


-- Trigger to call handle_new_user on new user creation in auth.users.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Function to create purchase orders from a list of suggestions.
-- This function is transactional and idempotent.
CREATE OR REPLACE FUNCTION public.create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid
)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    suggestion jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_po_number text;
    v_total_cost int;
    v_created_po_count int := 0;
BEGIN
    -- Check for idempotency
    IF EXISTS (SELECT 1 FROM purchase_orders WHERE idempotency_key = p_idempotency_key) THEN
        RETURN 0;
    END IF;

    -- Group suggestions by supplier_id
    FOR v_supplier_id IN
        SELECT DISTINCT (value->>'supplier_id')::uuid
        FROM jsonb_array_elements(p_suggestions)
    LOOP
        v_total_cost := 0;

        -- Create a new Purchase Order for the supplier
        v_po_number := 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || (
            SELECT COALESCE(MAX(SUBSTRING(po_number, '\d+$')::int), 0) + 1
            FROM purchase_orders
            WHERE company_id = p_company_id AND created_at::date = CURRENT_DATE
        );

        INSERT INTO purchase_orders (company_id, supplier_id, po_number, total_cost, status, idempotency_key)
        VALUES (p_company_id, v_supplier_id, v_po_number, 0, 'Ordered', p_idempotency_key)
        RETURNING id INTO v_po_id;

        v_created_po_count := v_created_po_count + 1;

        -- Add line items for each suggestion for this supplier
        FOR suggestion IN
            SELECT value FROM jsonb_array_elements(p_suggestions) WHERE (value->>'supplier_id')::uuid = v_supplier_id
        LOOP
            INSERT INTO purchase_order_line_items (company_id, purchase_order_id, variant_id, quantity, cost)
            VALUES (
                p_company_id,
                v_po_id,
                (suggestion->>'variant_id')::uuid,
                (suggestion->>'suggested_reorder_quantity')::int,
                (suggestion->>'unit_cost')::int
            );

            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::int * (suggestion->>'unit_cost')::int);
        END LOOP;

        -- Update the total cost of the PO
        UPDATE purchase_orders SET total_cost = v_total_cost WHERE id = v_po_id;

    END LOOP;

    RETURN v_created_po_count;
END;
$$;
COMMENT ON FUNCTION public.create_purchase_orders_from_suggestions IS 'Creates purchase orders grouped by supplier from a list of reorder suggestions.';


-- Function to check user permissions
CREATE OR REPLACE FUNCTION public.check_user_permission(p_user_id uuid, p_required_role text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_role text;
BEGIN
  SELECT role INTO user_role FROM public.users WHERE id = p_user_id;
  IF user_role = 'Owner' OR user_role = 'Admin' THEN
    RETURN true;
  END IF;
  RETURN false;
END;
$$;
COMMENT ON FUNCTION public.check_user_permission IS 'Checks if a user has the required role (Owner or Admin) to perform an action.';

--
-- Row-Level Security (RLS)
--

-- Helper function to apply RLS policies to all tables.
CREATE OR REPLACE FUNCTION public.enable_rls_for_all_tables()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    tbl_name text;
BEGIN
    -- Drop existing policies to ensure idempotency
    FOR tbl_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "Allow all access to own company data" ON public.' || quote_ident(tbl_name) || ';';
    END LOOP;

    -- Apply policies
    FOR tbl_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        IF tbl_name = 'companies' THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.companies FOR ALL USING (id = public.get_company_id());';
        ELSIF tbl_name = 'webhook_events' THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.webhook_events FOR ALL USING (integration_id IN (SELECT id FROM integrations WHERE company_id = public.get_company_id()));';
        ELSIF tbl_name = 'customer_addresses' THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.customer_addresses FOR ALL USING (customer_id IN (SELECT id FROM customers WHERE company_id = public.get_company_id()));';
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = tbl_name AND column_name = 'company_id') THEN
            EXECUTE 'CREATE POLICY "Allow all access to own company data" ON public.' || quote_ident(tbl_name) || ' FOR ALL USING (company_id = public.get_company_id());';
        END IF;
        
        EXECUTE 'ALTER TABLE public.' || quote_ident(tbl_name) || ' ENABLE ROW LEVEL SECURITY;';
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.enable_rls_for_all_tables() IS 'A helper function to enable RLS and apply a standard multi-tenant policy to all tables in the public schema.';


-- Initial invocation to secure the database.
SELECT public.enable_rls_for_all_tables();

-- Grant usage on schema and all tables to the authenticated role.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Allow anonymous users to call the handle_new_user function (via the trigger).
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_company_id() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_role() TO anon, authenticated;


-- Add a health check endpoint for testing database connectivity.
CREATE OR REPLACE FUNCTION public.health_check()
RETURNS text
LANGUAGE sql
AS $$
  SELECT 'OK';
$$;
GRANT EXECUTE ON FUNCTION public.health_check() TO anon, authenticated;
