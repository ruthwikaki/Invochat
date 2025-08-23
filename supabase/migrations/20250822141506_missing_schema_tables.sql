-- Apply Base Schema and Missing Tables
-- This ensures all required tables exist before other migrations

-- 1. Create base tables from main schema if they don't exist

-- Companies table to store company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name character varying,
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Users table to link Supabase auth users to companies
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    email character varying,
    company_id uuid,
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Products table (this is what was called "inventory" before)
CREATE TABLE IF NOT EXISTS public.products (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    sku text,
    name text,
    description text,
    category text,
    quantity integer DEFAULT 0,
    cost numeric(10,2) DEFAULT 0.00,
    price numeric(10,2) DEFAULT 0.00,
    reorder_point integer DEFAULT 0,
    reorder_qty integer DEFAULT 0,
    supplier_name text,
    warehouse_name text,
    last_sold_date date,
    created_at timestamp with time zone DEFAULT now(),
    shopify_product_id BIGINT,
    shopify_variant_id BIGINT,
    CONSTRAINT products_pkey PRIMARY KEY (id),
    CONSTRAINT products_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_products_shopify_ids ON public.products(company_id, shopify_product_id, shopify_variant_id);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Create inventory table as an alias/view for products for backward compatibility
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    sku text,
    name text,
    description text,
    category text,
    quantity integer DEFAULT 0,
    cost numeric(10,2) DEFAULT 0.00,
    price numeric(10,2) DEFAULT 0.00,
    reorder_point integer DEFAULT 0,
    reorder_qty integer DEFAULT 0,
    supplier_name text,
    warehouse_name text,
    last_sold_date date,
    created_at timestamp with time zone DEFAULT now(),
    shopify_product_id BIGINT,
    shopify_variant_id BIGINT,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Vendors/Suppliers table
CREATE TABLE IF NOT EXISTS public.vendors (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    vendor_name text,
    contact_info text,
    address text,
    terms text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT vendors_pkey PRIMARY KEY (id),
    CONSTRAINT vendors_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_vendors_company_id ON public.vendors(company_id);
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

-- Orders table (this is what handles sales)
CREATE TABLE IF NOT EXISTS public.orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    customer_name text,
    customer_email text,
    total_amount numeric(10,2) DEFAULT 0.00,
    financial_status text DEFAULT 'pending',
    fulfillment_status text DEFAULT 'unfulfilled',
    channel text DEFAULT 'manual',
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    shopify_order_id BIGINT,
    CONSTRAINT orders_pkey PRIMARY KEY (id),
    CONSTRAINT orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_shopify_id ON public.orders(company_id, shopify_order_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at);
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Order line items
CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    order_id uuid NOT NULL,
    company_id uuid NOT NULL,
    product_id uuid,
    sku text,
    product_name text,
    quantity integer DEFAULT 0,
    price numeric(10,2) DEFAULT 0.00,
    total_amount numeric(10,2) DEFAULT 0.00,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
    CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE,
    CONSTRAINT order_line_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_order_line_items_company_id ON public.order_line_items(company_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_sku ON public.order_line_items(sku);
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;

-- Purchase Orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    vendor_id uuid,
    status text DEFAULT 'pending',
    expected_date date,
    delivery_date date,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;

-- 2. Helper function to get company_id from user's claims
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id',
    (SELECT company_id FROM public.users WHERE id = auth.uid())
  )::uuid;
$$;

-- 3. RLS Policies
-- Policies for 'companies' table
DROP POLICY IF EXISTS "Users can view their own company" ON public.companies;
CREATE POLICY "Users can view their own company" ON public.companies FOR SELECT
USING (id = public.get_my_company_id());

-- Policies for 'users' table
DROP POLICY IF EXISTS "Users can view their own user record" ON public.users;
CREATE POLICY "Users can view their own user record" ON public.users FOR SELECT
USING (id = auth.uid());
DROP POLICY IF EXISTS "Users can update their own user record" ON public.users;
CREATE POLICY "Users can update their own user record" ON public.users FOR UPDATE
USING (id = auth.uid());

-- Policies for 'products' table
DROP POLICY IF EXISTS "Users can manage their own company's products" ON public.products;
CREATE POLICY "Users can manage their own company's products" ON public.products FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'inventory' table (backward compatibility)
DROP POLICY IF EXISTS "Users can manage their own company's inventory" ON public.inventory;
CREATE POLICY "Users can manage their own company's inventory" ON public.inventory FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'vendors' table
DROP POLICY IF EXISTS "Users can manage their own company's vendors" ON public.vendors;
CREATE POLICY "Users can manage their own company's vendors" ON public.vendors FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'orders' table
DROP POLICY IF EXISTS "Users can manage their own company's orders" ON public.orders;
CREATE POLICY "Users can manage their own company's orders" ON public.orders FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'order_line_items' table
DROP POLICY IF EXISTS "Users can manage their own company's order line items" ON public.order_line_items;
CREATE POLICY "Users can manage their own company's order line items" ON public.order_line_items FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'purchase_orders' table
DROP POLICY IF EXISTS "Users can manage their own company's purchase orders" ON public.purchase_orders;
CREATE POLICY "Users can manage their own company's purchase orders" ON public.purchase_orders FOR ALL
USING (company_id = public.get_my_company_id());

-- 4. User signup trigger
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Get company name from user's metadata
  user_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Insert a corresponding record into the public.users table
  INSERT INTO public.users (id, email, company_id)
  VALUES (new.id, new.email, new_company_id);

  -- Update the user's app_metadata with the new company_id
  -- This makes it available in the JWT for RLS checks
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
  WHERE id = new.id;

  RETURN new;
END;
$$;

-- Create the trigger that fires after a new user is created
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();