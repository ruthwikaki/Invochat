-- InvoChat App Schema
-- Run this script in your Supabase SQL Editor.
-- This script is idempotent and can be run multiple times safely.

-- 1. Create Tables

-- Companies table to store company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    name character varying,
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);
-- Add RLS
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
-- Add RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Inventory table
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
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
-- Add Indexes
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);
-- Add RLS
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Vendors table
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
-- Add Indexes
CREATE INDEX IF NOT EXISTS idx_vendors_company_id ON public.vendors(company_id);
-- Add RLS
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;

-- Purchase Orders table
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    vendor_id uuid,
    expected_date date,
    delivery_date date,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
    CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT purchase_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) ON DELETE SET NULL
);
-- Add Indexes
CREATE INDEX IF NOT EXISTS idx_po_company_id ON public.purchase_orders(company_id);
-- Add RLS
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;


-- 2. Define Row Level Security (RLS) Policies

-- Helper function to get company_id from user's claims
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    (current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata')::jsonb ->> 'company_id',
    (SELECT company_id FROM public.users WHERE id = auth.uid())
  )::uuid;
$$;

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


-- Policies for 'inventory' table
DROP POLICY IF EXISTS "Users can manage their own company's inventory" ON public.inventory;
CREATE POLICY "Users can manage their own company's inventory" ON public.inventory FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'vendors' table
DROP POLICY IF EXISTS "Users can manage their own company's vendors" ON public.vendors;
CREATE POLICY "Users can manage their own company's vendors" ON public.vendors FOR ALL
USING (company_id = public.get_my_company_id());

-- Policies for 'purchase_orders' table
DROP POLICY IF EXISTS "Users can manage their own company's purchase orders" ON public.purchase_orders;
CREATE POLICY "Users can manage their own company's purchase orders" ON public.purchase_orders FOR ALL
USING (company_id = public.get_my_company_id());


-- 3. Create Trigger Function for New User Signup

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


-- 4. Create RPC Functions

-- RPC for Chart Data
CREATE OR REPLACE FUNCTION public.get_chart_data(p_company_id uuid, p_query text)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    IF lower(p_query) LIKE '%inventory value by category%' THEN
        RETURN (
            SELECT json_agg(t)
            FROM (
                SELECT
                    category as name,
                    SUM(quantity * cost) as value
                FROM inventory
                WHERE company_id = p_company_id
                GROUP BY category
                ORDER BY value DESC
                LIMIT 10
            ) t
        );
    ELSIF lower(p_query) LIKE '%sales velocity by category%' THEN
        -- This is a placeholder as we don't have sales data.
        -- In a real app, you would query sales tables.
        RETURN (
            SELECT json_agg(t)
            FROM (
                SELECT
                    category as name,
                    SUM(quantity) as value -- Using quantity as a proxy for velocity
                FROM inventory
                WHERE company_id = p_company_id
                GROUP BY category
                ORDER BY value DESC
            ) t
        );
    ELSIF lower(p_query) LIKE '%warehouse distribution%' THEN
        RETURN (
            SELECT json_agg(t)
            FROM (
                SELECT
                    warehouse_name as name,
                    count(*) as value
                FROM inventory
                WHERE company_id = p_company_id AND warehouse_name IS NOT NULL
                GROUP BY warehouse_name
            ) t
        );
    ELSE
        -- Return empty array if no match
        RETURN '[]'::json;
    END IF;
END;
$$;

-- RPC for Supplier Performance (simplified)
-- This version returns a list of suppliers for the company.
CREATE OR REPLACE FUNCTION public.get_suppliers(p_company_id uuid)
RETURNS JSON
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN (
        SELECT json_agg(t)
        FROM (
            SELECT
                id,
                vendor_name as name,
                contact_info,
                address,
                terms
            FROM vendors
            WHERE company_id = p_company_id
        ) t
    );
END;
$$;
