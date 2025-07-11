-- Base schema for InvoChat
-- This script is designed to be idempotent, meaning it can be run multiple times safely.

-- 1. Extensions (if they don't exist)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Custom Types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
END$$;


-- 3. Tables (in order of dependency)

-- Companies table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Users table (references companies)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's users" ON public.users FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


-- Company Settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier numeric NOT NULL DEFAULT 3.0,
    high_value_threshold numeric NOT NULL DEFAULT 1000.00,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage settings for their own company" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


-- Suppliers table
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage suppliers for their own company" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_company_id_name_key;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name);

-- Inventory table
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost integer NOT NULL DEFAULT 0, -- In cents
    price integer, -- In cents
    reorder_point integer,
    last_sold_date date,
    supplier_id uuid,
    barcode text,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL,
    CONSTRAINT inventory_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT inventory_quantity_check CHECK (quantity >= 0)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage inventory for their own company" ON public.inventory FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_company_id_sku_key;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);

-- Inventory Ledger table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see ledger for their own company" ON public.inventory_ledger FOR SELECT USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

-- Customers table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage customers for their own company" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS customers_company_id_email_key;
ALTER TABLE public.customers ADD CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email);


-- Sales table
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sale_number text NOT NULL,
    customer_id uuid,
    customer_name text,
    customer_email text,
    total_amount integer NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    external_id text,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT sales_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage sales for their own company" ON public.sales FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_company_id_sale_number_key;
ALTER TABLE public.sales ADD CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number);

-- Sale Items table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage sale items for their own company" ON public.sale_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


-- Conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_accessed_at timestamptz NOT NULL DEFAULT now(),
    is_starred boolean NOT NULL DEFAULT false,
    CONSTRAINT conversations_pkey PRIMARY KEY (id),
    CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());


-- Messages table
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    visualization jsonb,
    component text,
    component_props jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamptz NOT NULL DEFAULT now(),
    is_error boolean NOT NULL DEFAULT false,
    CONSTRAINT messages_pkey PRIMARY KEY (id),
    CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
    CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage messages for their own company" ON public.messages FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


-- Channel Fees table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage channel fees for their own company" ON public.channel_fees FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.channel_fees DROP CONSTRAINT IF EXISTS channel_fees_company_id_channel_name_key;
ALTER TABLE public.channel_fees ADD CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name);

-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  CONSTRAINT integrations_pkey PRIMARY KEY (id),
  CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage integrations for their own company" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid())) WITH CHECK (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
ALTER TABLE public.integrations DROP CONSTRAINT IF EXISTS integrations_company_id_platform_key;
ALTER TABLE public.integrations ADD CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform);

-- 4. Triggers and Functions

-- Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create a corresponding user record
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      jsonb_set(
          COALESCE(app_metadata, '{}'::jsonb),
          '{company_id}',
          to_jsonb(new_company_id)
      ),
      '{role}',
      to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Drop existing trigger to ensure it can be recreated
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Trigger to call handle_new_user on new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();


-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS public.sales
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id uuid;
    new_sale_number text;
    v_customer_id uuid;
    item record;
    total_sale_amount integer := 0;
    current_stock integer;
BEGIN
    -- If customer email is provided, find or create the customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO v_customer_id FROM public.customers
        WHERE company_id = p_company_id AND email = p_customer_email;

        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email)
            VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Generate a new sale number
    SELECT COALESCE(MAX(SUBSTRING(sale_number FROM 'INV-(\d+)')::integer), 0) + 1 INTO new_sale_number
    FROM public.sales WHERE company_id = p_company_id;
    new_sale_number := 'INV-' || new_sale_number;

    -- Insert the main sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, customer_name, customer_email, total_amount, payment_method, notes, created_by, external_id)
    VALUES (p_company_id, new_sale_number, v_customer_id, p_customer_name, p_customer_email, 0, p_payment_method, p_notes, p_user_id, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Loop through sale items, update inventory, and insert sale_items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price integer, cost_at_time integer)
    LOOP
        -- Lock the inventory row for update
        SELECT quantity INTO current_stock FROM public.inventory WHERE id = item.product_id AND company_id = p_company_id FOR UPDATE;

        IF current_stock IS NULL THEN
            RAISE EXCEPTION 'Product with ID % not found for this company.', item.product_id;
        END IF;

        IF current_stock < item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product ID %. Available: %, Required: %', item.product_id, current_stock, item.quantity;
        END IF;

        -- Update inventory quantity
        UPDATE public.inventory
        SET
            quantity = quantity - item.quantity,
            last_sold_date = CURRENT_DATE,
            updated_at = now()
        WHERE id = item.product_id AND company_id = p_company_id;

        -- Insert into inventory ledger
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, item.product_id, 'sale', -item.quantity, current_stock - item.quantity, new_sale_id);

        -- Insert sale item record
        INSERT INTO public.sale_items (company_id, sale_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (p_company_id, new_sale_id, item.product_id, item.quantity, item.unit_price, item.cost_at_time);

        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Update the total amount on the sale record
    UPDATE public.sales SET total_amount = total_sale_amount WHERE id = new_sale_id;

    RETURN (SELECT * FROM public.sales WHERE id = new_sale_id);
END;
$$;


-- Add this new function to your schema
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS TABLE (
    dead_stock_value numeric,
    slow_mover_value numeric,
    dead_stock_threshold_days integer
)
LANGUAGE sql
STABLE
AS $$
    WITH settings AS (
        SELECT cs.dead_stock_days FROM public.company_settings cs WHERE cs.company_id = p_company_id
    )
    SELECT
        COALESCE(SUM(CASE WHEN i.last_sold_date IS NULL OR i.last_sold_date <= now() - (s.dead_stock_days || ' days')::interval THEN i.quantity * i.cost ELSE 0 END), 0)::numeric / 100 AS dead_stock_value,
        COALESCE(SUM(CASE WHEN i.last_sold_date > now() - (s.dead_stock_days || ' days')::interval AND i.last_sold_date <= now() - '30 days'::interval THEN i.quantity * i.cost ELSE 0 END), 0)::numeric / 100 AS slow_mover_value,
        s.dead_stock_days
    FROM
        public.inventory i,
        settings s
    WHERE
        i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0;
$$;

-- 5. Indexes for performance
CREATE INDEX IF NOT EXISTS idx_inventory_company_last_sold ON public.inventory (company_id, last_sold_date);
CREATE INDEX IF NOT EXISTS idx_sales_company_created_at ON public.sales (company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product ON public.inventory_ledger (company_id, product_id);


-- Final RLS setup
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));
