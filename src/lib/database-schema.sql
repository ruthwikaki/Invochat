-- InvoChat Database Schema
-- Version: 1.1.0
-- Description: This script sets up the necessary tables, roles, and functions for InvoChat.

-- Enable UUID extension for unique identifiers
create extension if not exists "uuid-ossp" with schema extensions;

-- Create a custom type for user roles to ensure data integrity
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


-- =================================================================
-- Tables
-- =================================================================

-- Companies Table: Stores basic information about each company tenant.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Users Table: Extends Supabase's auth.users with app-specific data.
CREATE TABLE IF NOT EXISTS public.users (
  id uuid NOT NULL,
  company_id uuid NOT NULL,
  email text,
  role public.user_role NOT NULL DEFAULT 'Member'::public.user_role,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid NOT NULL,
  dead_stock_days integer NOT NULL DEFAULT 90,
  fast_moving_days integer NOT NULL DEFAULT 30,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold numeric NOT NULL DEFAULT 100000,
  currency text DEFAULT 'USD'::text,
  timezone text DEFAULT 'UTC'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone,
  CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
  CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);


-- Suppliers Table
CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT suppliers_pkey PRIMARY KEY (id),
  CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_suppliers_name_company ON public.suppliers(company_id, name);


-- Inventory Table
CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  quantity integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  cost numeric NOT NULL DEFAULT 0, -- In cents
  price numeric, -- In cents
  reorder_point integer,
  last_sold_date date,
  barcode text,
  version integer NOT NULL DEFAULT 1,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone,
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  supplier_id uuid,
  CONSTRAINT inventory_pkey PRIMARY KEY (id),
  CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL,
  CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT inventory_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_inventory_sku_company ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_category ON public.inventory(company_id, category);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(deleted_at);


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  customer_name text NOT NULL,
  email text,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT customers_pkey PRIMARY KEY (id),
  CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT customers_company_id_email_key UNIQUE(company_id, email)
);

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  sale_number text NOT NULL,
  customer_id uuid,
  total_amount numeric NOT NULL, -- in cents
  payment_method text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  external_id text,
  CONSTRAINT sales_pkey PRIMARY KEY (id),
  CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
  CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(created_at);


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  sale_id uuid NOT NULL,
  company_id uuid NOT NULL,
  product_id uuid NOT NULL,
  sku text NOT NULL,
  product_name text,
  quantity integer NOT NULL,
  unit_price numeric NOT NULL, -- In cents
  cost_at_time numeric, -- In cents
  CONSTRAINT sale_items_pkey PRIMARY KEY (id),
  CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
  CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT,
  CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT sale_items_sale_id_product_id_key UNIQUE (sale_id, product_id)
);


-- Inventory Ledger Table: Transactional record of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  product_id uuid NOT NULL,
  change_type text NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
  quantity_change integer NOT NULL,
  new_quantity integer NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  related_id uuid, -- e.g., sale_id, purchase_order_id
  notes text,
  CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
  CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);

-- Conversations Table
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  company_id uuid NOT NULL,
  title text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  last_accessed_at timestamp with time zone DEFAULT now(),
  is_starred boolean DEFAULT false,
  CONSTRAINT conversations_pkey PRIMARY KEY (id),
  CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  conversation_id uuid NOT NULL,
  company_id uuid NOT NULL,
  role text NOT NULL,
  content text,
  component text,
  component_props jsonb,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  created_at timestamp with time zone DEFAULT now(),
  is_error boolean DEFAULT false,
  CONSTRAINT messages_pkey PRIMARY KEY (id),
  CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamp with time zone,
  sync_status text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone,
  CONSTRAINT integrations_pkey PRIMARY KEY (id),
  CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);

-- Sync State Table
CREATE TABLE IF NOT EXISTS public.sync_state (
  integration_id uuid NOT NULL,
  sync_type text NOT NULL,
  last_processed_cursor text,
  last_update timestamp with time zone,
  CONSTRAINT sync_state_pkey PRIMARY KEY (integration_id, sync_type),
  CONSTRAINT sync_state_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);

-- Sync Logs Table
CREATE TABLE IF NOT EXISTS public.sync_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  integration_id uuid NOT NULL,
  sync_type text,
  status text,
  records_synced integer,
  error_message text,
  started_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT sync_logs_pkey PRIMARY KEY (id),
  CONSTRAINT sync_logs_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  channel_name text NOT NULL,
  percentage_fee numeric NOT NULL,
  fixed_fee numeric NOT NULL, -- in cents
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone,
  CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
  CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);

-- Export Jobs Table
CREATE TABLE IF NOT EXISTS public.export_jobs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  requested_by_user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  download_url text,
  expires_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT export_jobs_pkey PRIMARY KEY (id),
  CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  company_id uuid,
  user_id uuid,
  action text NOT NULL,
  details jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT audit_log_pkey PRIMARY KEY (id),
  CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);


-- =================================================================
-- RLS Policies
-- =================================================================

-- Enable RLS for all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Helper function to get the company_id from a user's JWT claims
CREATE OR REPLACE FUNCTION auth.get_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Policies for 'companies' table
DROP POLICY IF EXISTS "Allow ALL for users of the same company" ON public.companies;
CREATE POLICY "Allow ALL for users of the same company"
ON public.companies
FOR ALL
USING (auth.uid() IS NOT NULL AND id = auth.get_company_id());

-- Policies for 'users' table
DROP POLICY IF EXISTS "Allow read access to own user record" ON public.users;
CREATE POLICY "Allow read access to own user record"
ON public.users
FOR SELECT
USING (auth.uid() = id);

DROP POLICY IF EXISTS "Allow read access to other users in the same company" ON public.users;
CREATE POLICY "Allow read access to other users in the same company"
ON public.users
FOR SELECT
USING (auth.uid() IS NOT NULL AND company_id = auth.get_company_id());

-- Policies for other tables based on company_id
CREATE OR REPLACE FUNCTION create_company_based_rls(table_name TEXT)
RETURNS void AS $$
BEGIN
    EXECUTE format('
        DROP POLICY IF EXISTS "Allow ALL for users of the same company" ON public.%I;
        CREATE POLICY "Allow ALL for users of the same company"
        ON public.%I
        FOR ALL
        USING (auth.uid() IS NOT NULL AND company_id = auth.get_company_id());
    ', table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply the generic company-based RLS policy to all relevant tables
SELECT create_company_based_rls('company_settings');
SELECT create_company_based_rls('inventory');
SELECT create_company_based_rls('suppliers');
SELECT create_company_based_rls('customers');
SELECT create_company_based_rls('sales');
SELECT create_company_based_rls('sale_items');
SELECT create_company_based_rls('inventory_ledger');
SELECT create_company_based_rls('conversations');
SELECT create_company_based_rls('messages');
SELECT create_company_based_rls('integrations');
SELECT create_company_based_rls('channel_fees');
SELECT create_company_based_rls('export_jobs');
SELECT create_company_based_rls('audit_log');


-- RLS for join tables that might not have a direct company_id
DROP POLICY IF EXISTS "Allow ALL on sync_state for company users" ON public.sync_state;
CREATE POLICY "Allow ALL on sync_state for company users"
ON public.sync_state
FOR ALL
USING (
  auth.uid() IS NOT NULL AND
  EXISTS (
    SELECT 1 FROM public.integrations i
    WHERE i.id = sync_state.integration_id AND i.company_id = auth.get_company_id()
  )
);

DROP POLICY IF EXISTS "Allow ALL on sync_logs for company users" ON public.sync_logs;
CREATE POLICY "Allow ALL on sync_logs for company users"
ON public.sync_logs
FOR ALL
USING (
  auth.uid() IS NOT NULL AND
  EXISTS (
    SELECT 1 FROM public.integrations i
    WHERE i.id = sync_logs.integration_id AND i.company_id = auth.get_company_id()
  )
);

-- =================================================================
-- DB Functions
-- =================================================================

-- Function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Check if user was invited (has company_id in metadata)
  IF new.raw_app_meta_data->>'company_id' IS NOT NULL THEN
    company_id := (new.raw_app_meta_data->>'company_id')::uuid;
  ELSE
    -- User signed up directly, create a new company for them
    company_name := COALESCE(new.raw_user_meta_data->>'company_name', 'My Company');
    INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO company_id;

    -- Update the user's app_metadata with the new company_id and Owner role
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', 'Owner')
    WHERE id = new.id;
  END IF;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (
    new.id,
    company_id,
    new.email,
    (new.raw_app_meta_data->>'role')::public.user_role
  );
  
  -- Insert default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (company_id);
  
  RETURN new;
END;
$$;

-- Trigger to call handle_new_user on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to update inventory and create ledger entry
CREATE OR REPLACE FUNCTION public.update_inventory_and_log(
    p_company_id uuid,
    p_product_id uuid,
    p_quantity_change integer,
    p_change_type text,
    p_related_id uuid DEFAULT NULL,
    p_notes text DEFAULT NULL
)
RETURNS void AS $$
DECLARE
    v_new_quantity integer;
BEGIN
    UPDATE public.inventory
    SET quantity = quantity + p_quantity_change
    WHERE id = p_product_id AND company_id = p_company_id
    RETURNING quantity INTO v_new_quantity;

    IF v_new_quantity IS NULL THEN
        RAISE EXCEPTION 'Product with ID % not found for company %', p_product_id, p_company_id;
    END IF;

    INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (p_company_id, p_product_id, p_change_type, p_quantity_change, v_new_quantity, p_related_id, p_notes);
END;
$$ LANGUAGE plpgsql;


-- Function to record a sale and update inventory
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
RETURNS public.sales AS $$
DECLARE
    v_sale_id uuid;
    v_customer_id uuid;
    v_total_amount numeric := 0;
    v_sale_number text;
    v_item RECORD;
    v_product_cost numeric;
    v_sale_record public.sales;
BEGIN
    -- Upsert customer and get ID
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total amount
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price numeric)
    LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    -- Generate a unique sale number
    SELECT COALESCE(MAX(SUBSTRING(sale_number, 4)::integer), 0) + 1 INTO v_sale_number
    FROM public.sales
    WHERE company_id = p_company_id;
    v_sale_number := 'INV' || LPAD(v_sale_number::text, 6, '0');

    -- Insert into sales table
    INSERT INTO public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, v_sale_number, v_customer_id, v_total_amount, p_payment_method, p_notes, p_external_id)
    RETURNING * INTO v_sale_record;
    v_sale_id := v_sale_record.id;
    
    -- Insert sale items and update inventory
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, product_name text, quantity integer, unit_price numeric)
    LOOP
        -- Get current cost of the product
        SELECT cost INTO v_product_cost FROM public.inventory WHERE id = v_item.product_id;

        INSERT INTO public.sale_items (sale_id, company_id, product_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (v_sale_id, p_company_id, v_item.product_id, (SELECT sku FROM inventory WHERE id = v_item.product_id), v_item.product_name, v_item.quantity, v_item.unit_price, v_product_cost);

        -- Update inventory quantity and log the change
        PERFORM public.update_inventory_and_log(
            p_company_id,
            v_item.product_id,
            -v_item.quantity,
            'sale',
            v_sale_id
        );

        -- Update last_sold_date on the inventory item
        UPDATE public.inventory
        SET last_sold_date = now()::date
        WHERE id = v_item.product_id;
    END LOOP;

    RETURN v_sale_record;
END;
$$ LANGUAGE plpgsql;

-- Function to safely purge soft-deleted data after a retention period
CREATE OR REPLACE FUNCTION public.purge_soft_deleted_data(p_retention_days integer)
RETURNS void AS $$
DECLARE
    v_cutoff_date timestamp;
BEGIN
    v_cutoff_date := now() - (p_retention_days || ' days')::interval;

    -- Purge inventory
    DELETE FROM public.inventory WHERE deleted_at <= v_cutoff_date;
    -- Purge customers
    DELETE FROM public.customers WHERE deleted_at <= v_cutoff_date;
    -- Purge users
    DELETE FROM public.users WHERE deleted_at <= v_cutoff_date;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- =================================================================
-- New Analytics Functions
-- =================================================================

CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE(sku text, product_name text, quantity integer, total_value integer, days_since_last_sale integer)
LANGUAGE sql STABLE
AS $$
  SELECT
    i.sku,
    i.name as product_name,
    i.quantity,
    (i.quantity * i.cost)::integer as total_value,
    (now()::date - COALESCE(i.last_sold_date, i.created_at::date))::integer as days_since_last_sale
  FROM public.inventory i
  WHERE i.company_id = p_company_id
    AND i.deleted_at IS NULL
    AND i.quantity > 0
  ORDER BY days_since_last_sale DESC;
$$;


CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    result json;
BEGIN
    WITH product_sales_trends AS (
        SELECT
            p.id as product_id,
            p.sku,
            p.name as product_name,
            p.created_at,
            (now()::date - p.created_at::date) as age_days,
            SUM(si.quantity) as total_sales_quantity,
            SUM(si.unit_price * si.quantity) as total_revenue,
            -- Sales in the last 90 days
            SUM(CASE WHEN s.created_at >= now() - interval '90 days' THEN si.quantity ELSE 0 END) as sales_last_90d,
            -- Sales in the 90 days before that
            SUM(CASE WHEN s.created_at >= now() - interval '180 days' AND s.created_at < now() - interval '90 days' THEN si.quantity ELSE 0 END) as sales_prev_90d
        FROM public.inventory p
        JOIN public.sale_items si ON p.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE p.company_id = p_company_id AND p.deleted_at IS NULL AND s.company_id = p_company_id
        GROUP BY p.id
    ),
    product_stages AS (
        SELECT
            *,
            CASE
                -- Launch: First sale within last 60 days and product is new
                WHEN age_days <= 60 AND total_sales_quantity > 0 THEN 'Launch'
                -- Growth: Sales in last 90d are > 20% higher than previous 90d
                WHEN sales_last_90d > sales_prev_90d * 1.2 AND sales_prev_90d > 0 THEN 'Growth'
                -- Decline: Sales in last 90d are < 20% lower than previous 90d
                WHEN sales_last_90d < sales_prev_90d * 0.8 AND sales_last_90d > 0 THEN 'Decline'
                -- Maturity: Stable sales
                ELSE 'Maturity'
            END as stage
        FROM product_sales_trends
    )
    SELECT json_build_object(
        'summary', (
            SELECT json_build_object(
                'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
                'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
                'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
                'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
            ) FROM product_stages
        ),
        'products', (SELECT json_agg(p) FROM product_stages p)
    ) INTO result;

    RETURN result;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    risk_score integer,
    risk_level text,
    total_value integer,
    reason text
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_max_days_since_sale float;
    v_max_inventory_value float;
BEGIN
    SELECT 
        GREATEST(1.0, MAX((now()::date - COALESCE(i.last_sold_date, i.created_at::date))::integer))::float,
        GREATEST(1.0, MAX(i.quantity * i.cost))::float
    INTO
        v_max_days_since_sale,
        v_max_inventory_value
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0;

    RETURN QUERY
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name as product_name,
            (i.quantity * i.cost) as inventory_value,
            (now()::date - COALESCE(i.last_sold_date, i.created_at::date))::integer as days_since_last_sale
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    )
    SELECT
        rf.sku,
        rf.product_name,
        -- Calculate risk score (0-100)
        (
            -- 60% weight on how long it's been sitting
            (rf.days_since_last_sale / v_max_days_since_sale) * 60 +
            -- 40% weight on how much capital is tied up
            (rf.inventory_value / v_max_inventory_value) * 40
        )::integer as risk_score,
        CASE
            WHEN ( (rf.days_since_last_sale / v_max_days_since_sale) * 60 + (rf.inventory_value / v_max_inventory_value) * 40 ) > 75 THEN 'High'
            WHEN ( (rf.days_since_last_sale / v_max_days_since_sale) * 60 + (rf.inventory_value / v_max_inventory_value) * 40 ) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        rf.inventory_value::integer,
        'Days unsold: ' || rf.days_since_last_sale || ', Value: $' || (rf.inventory_value / 100)::text as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue bigint
)
LANGUAGE sql STABLE
AS $$
WITH customer_segments AS (
    SELECT
        c.id,
        CASE
            WHEN s.order_count = 1 THEN 'New Customers'
            WHEN s.order_count > 1 THEN 'Repeat Customers'
        END as segment,
        CASE
            -- Top 20% of spenders are 'Top Spenders'
            WHEN s.total_spent > (SELECT percentile_cont(0.8) WITHIN GROUP (ORDER BY total_spent) FROM (SELECT SUM(total_amount) as total_spent FROM sales WHERE company_id = p_company_id GROUP BY customer_id) as spending) THEN 'Top Spenders'
        END as top_spender_segment
    FROM public.customers c
    JOIN (
        SELECT customer_id, COUNT(*) as order_count, SUM(total_amount) as total_spent
        FROM public.sales
        WHERE customer_id IS NOT NULL AND company_id = p_company_id
        GROUP BY customer_id
    ) s ON c.id = s.customer_id
    WHERE c.company_id = p_company_id
)
SELECT
    COALESCE(cs.top_spender_segment, cs.segment) as segment,
    si.sku,
    si.product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.unit_price * si.quantity)::bigint as total_revenue
FROM public.sale_items si
JOIN public.sales s ON si.sale_id = s.id
JOIN customer_segments cs ON s.customer_id = cs.id
WHERE si.company_id = p_company_id
GROUP BY 1, 2, 3
ORDER BY segment, total_revenue DESC;
$$;


CREATE OR REPLACE FUNCTION public.get_profit_warning_alerts(p_company_id uuid)
RETURNS TABLE(
    product_id uuid,
    product_name text,
    sku text,
    recent_margin numeric,
    previous_margin numeric
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    WITH sales_with_margin AS (
        SELECT
            si.product_id,
            s.created_at,
            ((si.unit_price - si.cost_at_time) / NULLIF(si.unit_price, 0)) as margin
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE si.company_id = p_company_id AND si.cost_at_time IS NOT NULL AND si.unit_price > 0
    ),
    margin_periods AS (
        SELECT
            product_id,
            -- Avg margin in last 90 days
            AVG(margin) FILTER (WHERE created_at >= now() - interval '90 days') as recent_margin,
            -- Avg margin in the 90 days before that
            AVG(margin) FILTER (WHERE created_at >= now() - interval '180 days' AND created_at < now() - interval '90 days') as previous_margin
        FROM sales_with_margin
        GROUP BY product_id
    )
    SELECT
        mp.product_id,
        i.name as product_name,
        i.sku,
        mp.recent_margin,
        mp.previous_margin
    FROM margin_periods mp
    JOIN public.inventory i ON mp.product_id = i.id
    WHERE mp.recent_margin IS NOT NULL
      AND mp.previous_margin IS NOT NULL
      -- Trigger alert if margin dropped by more than 10 percentage points (e.g., from 50% to 39%)
      AND mp.recent_margin < (mp.previous_margin - 0.10);
END;
$$;

-- Modify the main get_alerts function to include profit warnings
CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid)
RETURNS TABLE(
    id text,
    type text,
    title text,
    message text,
    severity text,
    "timestamp" timestamptz,
    metadata jsonb
)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_settings record;
BEGIN
    SELECT * INTO v_settings FROM public.company_settings WHERE company_id = p_company_id;

    -- Low Stock Alerts
    RETURN QUERY
    SELECT
        'low_stock_' || i.id::text,
        'low_stock',
        'Low Stock Warning',
        i.name || ' is running low on stock.',
        'warning',
        now(),
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'reorderPoint', i.reorder_point
        )
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity > 0
      AND i.reorder_point IS NOT NULL
      AND i.quantity < i.reorder_point;

    -- Dead Stock Alerts
    RETURN QUERY
    SELECT
        'dead_stock_' || i.id::text,
        'dead_stock',
        'Dead Stock Alert',
        i.name || ' has not sold in over ' || v_settings.dead_stock_days || ' days.',
        'critical',
        now(),
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'lastSoldDate', i.last_sold_date,
            'value', (i.quantity * i.cost)
        )
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity > 0
      AND (now()::date - COALESCE(i.last_sold_date, i.created_at::date)) > v_settings.dead_stock_days;
      
    -- Profit Warning Alerts
    RETURN QUERY
    SELECT
        'profit_warning_' || pwa.product_id::text,
        'profit_warning',
        'Profit Margin Warning',
        'The profit margin for ' || pwa.product_name || ' has dropped significantly.',
        'critical',
        now(),
        jsonb_build_object(
            'productId', pwa.product_id,
            'productName', pwa.product_name,
            'recent_margin', pwa.recent_margin,
            'previous_margin', pwa.previous_margin
        )
    FROM public.get_profit_warning_alerts(p_company_id) pwa;

END;
$$;


CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_dead_stock_days integer;
    v_slow_mover_days integer;
BEGIN
    SELECT cs.dead_stock_days INTO v_dead_stock_days FROM public.company_settings cs WHERE cs.company_id = p_company_id;
    v_slow_mover_days := 30;

    RETURN (
        WITH stock_ages AS (
            SELECT
                i.id,
                (i.quantity * i.cost) as total_value,
                (now()::date - COALESCE(i.last_sold_date, i.created_at::date)) as age_days
            FROM public.inventory i
            WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
        )
        SELECT json_build_object(
            'dead_stock_value', COALESCE(SUM(total_value) FILTER (WHERE age_days > v_dead_stock_days), 0)::integer,
            'slow_mover_value', COALESCE(SUM(total_value) FILTER (WHERE age_days BETWEEN v_slow_mover_days AND v_dead_stock_days), 0)::integer,
            'dead_stock_threshold_days', v_dead_stock_days
        )
        FROM stock_ages
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS json
LANGUAGE plpgsql STABLE
AS $$
DECLARE
    v_result json;
    v_price_elasticity numeric := 1.5; -- Assumption: for every 10% discount, sales increase by 15%
BEGIN
    WITH promo_items AS (
        SELECT
            i.id,
            i.sku,
            i.name,
            i.price,
            i.cost,
            -- Calculate avg daily sales over last 90 days
            (
                SELECT COALESCE(SUM(si.quantity), 0)
                FROM public.sale_items si
                JOIN public.sales s ON si.sale_id = s.id
                WHERE si.product_id = i.id AND s.created_at >= now() - interval '90 days'
            ) / 90.0 as avg_daily_sales
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    ),
    analysis AS (
        SELECT
            sku,
            name,
            price as original_price,
            price * (1 - p_discount_percentage) as discounted_price,
            cost,
            -- Projected sales increase
            avg_daily_sales * (1 + (p_discount_percentage / 0.10) * v_price_elasticity) as projected_daily_sales,
            avg_daily_sales as baseline_daily_sales
        FROM promo_items
    )
    SELECT json_build_object(
        'original_revenue', (SELECT SUM(baseline_daily_sales * original_price) FROM analysis) * p_duration_days,
        'original_profit', (SELECT SUM(baseline_daily_sales * (original_price - cost)) FROM analysis) * p_duration_days,
        'projected_revenue', (SELECT SUM(projected_daily_sales * discounted_price) FROM analysis) * p_duration_days,
        'projected_profit', (SELECT SUM(projected_daily_sales * (discounted_price - cost)) FROM analysis) * p_duration_days,
        'items', (SELECT json_agg(analysis) FROM analysis)
    ) INTO v_result;

    RETURN v_result;
END;
$$;
