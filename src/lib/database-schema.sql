-- =================================================================
-- 0. EXTENSIONS & HELPER FUNCTIONS
-- =================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Function to get the current user's company_id from their JWT claims
DROP FUNCTION IF EXISTS public.get_current_company_id();
CREATE OR REPLACE FUNCTION public.get_current_company_id()
RETURNS uuid AS $$
BEGIN
    -- This handles cases where the claim might be missing or not a valid UUID format
    RETURN (auth.jwt()->'app_metadata'->>'company_id')::uuid;
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- 1. DROP OLD TABLES AND FUNCTIONS IN CORRECT ORDER
-- =================================================================
-- This section ensures the script is idempotent and can be re-run safely.

-- Drop old foreign key constraints first
ALTER TABLE IF EXISTS public.inventory DROP CONSTRAINT IF EXISTS inventory_supplier_id_fkey;
ALTER TABLE IF EXISTS public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_product_id_fkey;
ALTER TABLE IF EXISTS public.sale_items DROP CONSTRAINT IF EXISTS sale_items_product_id_fkey;
ALTER TABLE IF EXISTS public.sale_items DROP CONSTRAINT IF EXISTS sale_items_sale_id_fkey;
ALTER TABLE IF EXISTS public.sales DROP CONSTRAINT IF EXISTS sales_customer_id_fkey;

-- Drop dependent functions before dropping tables they use
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

-- Now drop the old, simplified tables
DROP TABLE IF EXISTS public.sale_items;
DROP TABLE IF EXISTS public.sales;
DROP TABLE IF EXISTS public.inventory_ledger;
DROP TABLE IF EXISTS public.inventory;


-- =================================================================
-- 2. CORE TABLE CREATION (SAAS-READY SCHEMA)
-- =================================================================

-- Base entity for a physical product
CREATE TABLE IF NOT EXISTS public.products (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text, -- e.g., 'active', 'archived', 'draft'
    image_url text,
    external_product_id text, -- ID from the source platform (e.g., Shopify's product ID)
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);

-- Variants of a product (e.g., specific sizes, colors)
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
    compare_at_price integer, -- Price in cents
    cost integer, -- Cost in cents
    inventory_quantity integer NOT NULL DEFAULT 0,
    external_variant_id text, -- ID from the source platform (e.g., Shopify's variant ID)
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(sku);

-- Customer records
ALTER TABLE public.customers
    ADD COLUMN IF NOT EXISTS external_customer_id text,
    ADD COLUMN IF NOT EXISTS phone text,
    ADD COLUMN IF NOT EXISTS last_order_date date;

-- Customer Addresses
CREATE TABLE IF NOT EXISTS public.customer_addresses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    address_type text NOT NULL DEFAULT 'shipping', -- billing/shipping
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

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer, -- in cents
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer,
    source_platform text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- Order Line Items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer, -- Price per unit in cents
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);

-- Discounts
CREATE TABLE IF NOT EXISTS public.discounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    code text NOT NULL,
    type text NOT NULL, -- percentage/fixed_amount/free_shipping
    value numeric NOT NULL,
    minimum_purchase integer, -- in cents
    usage_limit integer,
    usage_count integer DEFAULT 0,
    applies_to text DEFAULT 'all', -- all/specific_products/collections
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_discounts_company_id ON public.discounts(company_id);

-- Inventory Adjustments (for manual changes, cycle counts, etc.)
CREATE TABLE IF NOT EXISTS public.inventory_adjustments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    variant_id uuid NOT NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
    change_type text NOT NULL, -- e.g., 'restock', 'sale', 'return', 'count_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- Can link to an order, refund, purchase order, etc.
    notes text,
    created_at timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inventory_adjustments_variant_id ON public.inventory_adjustments(variant_id);

-- =================================================================
-- 3. IDEMPOTENTLY ADD UNIQUE CONSTRAINTS
-- =================================================================

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS unique_external_product_id_per_company;
ALTER TABLE public.products ADD CONSTRAINT unique_external_product_id_per_company UNIQUE (company_id, external_product_id);

ALTER TABLE public.product_variants DROP CONSTRAINT IF EXISTS unique_sku_per_company;
ALTER TABLE public.product_variants ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_external_order_id_per_company;
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_id_per_company UNIQUE (company_id, external_order_id);

-- =================================================================
-- 4. RECREATE FUNCTIONS AND TRIGGERS
-- =================================================================

-- Function to create a new company and user profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Create a new company for the user
  company_name := new.raw_app_meta_data->>'company_name';
  IF company_name IS NULL OR company_name = '' THEN
    company_name := new.email || '''s Company';
  END IF;

  INSERT INTO public.companies (name) VALUES (company_name)
  RETURNING id INTO new_company_id;

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  -- Create a settings entry for the new company
  INSERT INTO public.company_settings (company_id) VALUES (new_company_id);

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to execute the function on new user creation in auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to automatically update 'updated_at' columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply the trigger to all tables that have an 'updated_at' column
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON public.product_variants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- 5. ROW-LEVEL SECURITY (RLS)
-- =================================================================
-- This is the most critical part for a SaaS application.

-- Enable RLS for all relevant tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to ensure idempotency
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.products;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.product_variants;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customers;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.customer_addresses;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.orders;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.order_line_items;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.discounts;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.inventory_adjustments;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.company_settings;
DROP POLICY IF EXISTS "Users can only see their own company's data." ON public.integrations;

-- Create policies that restrict access based on the user's company_id claim
CREATE POLICY "Users can only see their own company's data." ON public.products FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.product_variants FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.customers FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.customer_addresses FOR ALL
    USING (company_id = public.get_current_company_id());
    
CREATE POLICY "Users can only see their own company's data." ON public.orders FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.order_line_items FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.discounts FOR ALL
    USING (company_id = public.get_current_company_id());

CREATE POLICY "Users can only see their own company's data." ON public.inventory_adjustments FOR ALL
    USING (company_id = public.get_current_company_id());
    
CREATE POLICY "Users can only see their own company's data." ON public.company_settings FOR ALL
    USING (company_id = public.get_current_company_id());
    
CREATE POLICY "Users can only see their own company's data." ON public.integrations FOR ALL
    USING (company_id = public.get_current_company_id());

-- Grant usage on schema to roles
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;

-- Grant all permissions to the authenticated role for new tables
GRANT ALL ON TABLE public.products TO authenticated;
GRANT ALL ON TABLE public.product_variants TO authenticated;
GRANT ALL ON TABLE public.customer_addresses TO authenticated;
GRANT ALL ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.order_line_items TO authenticated;
GRANT ALL ON TABLE public.discounts TO authenticated;
GRANT ALL ON TABLE public.inventory_adjustments TO authenticated;

-- Grant all permissions to the service_role for direct backend access
GRANT ALL ON TABLE public.products TO service_role;
GRANT ALL ON TABLE public.product_variants TO service_role;
GRANT ALL ON TABLE public.customer_addresses TO service_role;
GRANT ALL ON TABLE public.orders TO service_role;
GRANT ALL ON TABLE public.order_line_items TO service_role;
GRANT ALL ON TABLE public.discounts TO service_role;
GRANT ALL ON TABLE public.inventory_adjustments TO service_role;
