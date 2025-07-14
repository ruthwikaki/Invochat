-- Enable the pgcrypto extension for UUID generation
create extension if not exists pgcrypto with schema extensions;

-- Create a custom type for user roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-----------------------------------------
-- TABLES
-----------------------------------------

-- Table for Companies
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table for User Profiles (links to auth.users)
-- This table stores app-specific user data and is owned by the user.
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    first_name TEXT,
    last_name TEXT,
    role public.user_role NOT NULL DEFAULT 'Member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
-- Add indexes for common lookups
CREATE INDEX IF NOT EXISTS idx_profiles_company_id ON public.profiles(company_id);

-- Table for Company-Specific Settings
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier INT NOT NULL DEFAULT 3,
    high_value_threshold INT NOT NULL DEFAULT 1000,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);

-- Table for Suppliers/Vendors
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Table for Products (Parent Record)
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    handle TEXT,
    product_type TEXT, -- This is the 'category'
    tags TEXT[],
    status TEXT,
    image_url TEXT,
    external_product_id TEXT, -- For linking to external platforms
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_product_id)
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_external_id ON public.products(external_product_id);
-- Secure full-text search index
CREATE INDEX IF NOT EXISTS products_title_search_idx ON public.products USING gin (to_tsvector('english', title));


-- Table for Product Variants (SKUs)
-- This table holds the actual inventory information.
CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT,
    title TEXT, -- e.g., "Small", "Red"
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
    location TEXT NULL, -- Simplified location as a text field
    external_variant_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, sku),
    UNIQUE(company_id, external_variant_id)
);
CREATE INDEX IF NOT EXISTS idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_variants_company_id ON public.product_variants(company_id);
CREATE INDEX IF NOT EXISTS idx_variants_sku ON public.product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_variants_external_id ON public.product_variants(external_variant_id);


-- Table for Customers
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT,
    email TEXT,
    total_orders INT DEFAULT 0,
    total_spent INT DEFAULT 0, -- in cents
    first_order_date DATE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers(email);


-- Table for Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number TEXT NOT NULL,
    external_order_id TEXT,
    customer_id UUID REFERENCES public.customers(id),
    financial_status TEXT,
    fulfillment_status TEXT,
    currency TEXT,
    subtotal INT NOT NULL DEFAULT 0,
    total_tax INT DEFAULT 0,
    total_shipping INT DEFAULT 0,
    total_discounts INT DEFAULT 0,
    total_amount INT NOT NULL,
    source_platform TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, external_order_id)
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_external_id ON public.orders(external_order_id);


-- Table for Order Line Items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name TEXT,
    variant_title TEXT,
    sku TEXT,
    quantity INT NOT NULL,
    price INT NOT NULL,
    total_discount INT DEFAULT 0,
    tax_amount INT DEFAULT 0,
    cost_at_time INT,
    external_line_item_id TEXT,
    UNIQUE(order_id, external_line_item_id)
);
CREATE INDEX IF NOT EXISTS idx_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_line_items_company_id ON public.order_line_items(company_id);

-- Table for Inventory Ledger
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id BIGSERIAL PRIMARY KEY,
    variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL, -- e.g., 'sale', 'purchase_order', 'reconciliation', 'manual_adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    notes TEXT,
    related_id UUID, -- e.g., order_id, purchase_order_id
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_variant_id ON public.inventory_ledger(variant_id);
CREATE INDEX IF NOT EXISTS idx_ledger_company_id ON public.inventory_ledger(company_id);

-- Table for Integrations
CREATE TABLE IF NOT EXISTS public.integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN DEFAULT false,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, platform)
);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- Table for Purchase Orders
CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'Draft', -- e.g., Draft, Ordered, Partially Received, Received, Cancelled
  po_number TEXT NOT NULL,
  total_cost INT NOT NULL,
  expected_arrival_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(company_id, po_number)
);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
CREATE INDEX IF NOT EXISTS idx_po_supplier_id ON public.purchase_orders(supplier_id);


-- Table for Purchase Order Line Items
CREATE TABLE IF NOT EXISTS public.purchase_order_line_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
  variant_id UUID NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  quantity INT NOT NULL,
  cost INT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_po_items_po_id ON public.purchase_order_line_items(purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_po_items_variant_id ON public.purchase_order_line_items(variant_id);

-- Table to prevent webhook replay attacks
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  webhook_id TEXT NOT NULL,
  processed_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(integration_id, webhook_id)
);


-----------------------------------------
-- VIEWS
-----------------------------------------

-- Drop the view first to avoid column order errors on recreation
DROP VIEW IF EXISTS public.product_variants_with_details;

-- Create a view for a unified look at inventory with all details
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title as product_title,
    p.product_type,
    p.status as product_status,
    p.image_url,
    s.name as supplier_name,
    s.id as supplier_id
FROM
    public.product_variants pv
JOIN
    public.products p ON pv.product_id = p.id
LEFT JOIN
    public.suppliers s ON p.company_id = s.company_id AND p.title ILIKE '%' || s.name || '%'; -- This is a simple heuristic, a dedicated supplier link table would be better


-----------------------------------------
-- FUNCTIONS
-----------------------------------------

-- Function to get the current user's company_id from their profile
-- This is secure because it uses the JWT to identify the user.
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS UUID AS $$
DECLARE
    company_uuid UUID;
BEGIN
    SELECT company_id INTO company_uuid
    FROM public.profiles
    WHERE id = auth.uid()
    LIMIT 1;
    RETURN company_uuid;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;


-- Function to handle new user sign-ups
-- This function is called by a trigger when a new user is created in auth.users.
CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
    company_uuid UUID;
BEGIN
    -- 1. Create a new company for the user.
    INSERT INTO public.companies (name)
    VALUES (new.raw_app_meta_data->>'company_name')
    RETURNING id INTO company_uuid;

    -- 2. Create a profile for the new user, linking them to the new company as 'Owner'.
    INSERT INTO public.profiles (id, company_id, first_name, last_name, role)
    VALUES (
        new.id,
        company_uuid,
        new.raw_user_meta_data->>'first_name',
        new.raw_user_meta_data->>'last_name',
        'Owner'
    );
    
    -- 3. Update the user's app_metadata in the auth schema with the new company_id.
    -- This makes it easily accessible in JWT claims.
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_uuid, 'role', 'Owner')
    WHERE id = new.id;
    
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-----------------------------------------
-- TRIGGERS
-----------------------------------------

-- Drop existing trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created_trigger ON auth.users;

-- Create the trigger that fires after a new user is inserted into auth.users.
CREATE TRIGGER on_auth_user_created_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.on_auth_user_created();


-----------------------------------------
-- ROW-LEVEL SECURITY (RLS)
-----------------------------------------

-- Enable RLS for all relevant tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating new ones
DROP POLICY IF EXISTS "Allow all access to own company" ON public.companies;
DROP POLICY IF EXISTS "Allow all access to own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow all access to own company settings" ON public.company_settings;
DROP POLICY IF EXISTS "Allow all access to own products" ON public.products;
DROP POLICY IF EXISTS "Allow all access to own variants" ON public.product_variants;
DROP POLICY IF EXISTS "Allow all access to own suppliers" ON public.suppliers;
DROP POLICY IF EXISTS "Allow all access to own customers" ON public.customers;
DROP POLICY IF EXISTS "Allow all access to own orders" ON public.orders;
DROP POLICY IF EXISTS "Allow all access to own order line items" ON public.order_line_items;
DROP POLICY IF EXISTS "Allow all access to own ledger" ON public.inventory_ledger;
DROP POLICY IF EXISTS "Allow all access to own integrations" ON public.integrations;
DROP POLICY IF EXISTS "Allow all access to own purchase orders" ON public.purchase_orders;
DROP POLICY IF EXISTS "Allow all access to own PO line items" ON public.purchase_order_line_items;
DROP POLICY IF EXISTS "Allow all access to own webhook events" ON public.webhook_events;


-- --- POLICIES ---
-- Policies restrict data access to users within the same company.

CREATE POLICY "Allow all access to own company"
ON public.companies FOR ALL
USING (id = public.get_current_company_id());

CREATE POLICY "Allow all access to own profile"
ON public.profiles FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own company settings"
ON public.company_settings FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own products"
ON public.products FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own variants"
ON public.product_variants FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own suppliers"
ON public.suppliers FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own customers"
ON public.customers FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own orders"
ON public.orders FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own order line items"
ON public.order_line_items FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own ledger"
ON public.inventory_ledger FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own integrations"
ON public.integrations FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own purchase orders"
ON public.purchase_orders FOR ALL
USING (company_id = public.get_current_company_id());

CREATE POLICY "Allow all access to own PO line items"
ON public.purchase_order_line_items FOR ALL
USING (purchase_order_id IN (SELECT id FROM public.purchase_orders WHERE company_id = public.get_current_company_id()));

CREATE POLICY "Allow all access to own webhook events"
ON public.webhook_events FOR ALL
USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_current_company_id()));


-- Grant usage on the public schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;
-- Grant all privileges on all tables in the public schema to the authenticated role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO authenticated;
