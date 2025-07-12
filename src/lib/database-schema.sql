
-- This script is idempotent and can be run multiple times.
-- =================================================================
-- 1. Setup Custom Types
-- =================================================================
-- Drop the type if it exists to ensure a clean slate
DROP TYPE IF EXISTS public.user_role CASCADE;
-- Create the custom type for user roles
CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');


-- =================================================================
-- 2. Create Core Tables
-- =================================================================

-- Companies Table: Stores company-specific information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;


-- Users Table: Extends auth.users with app-specific data
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;


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
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;


-- Inventory Table
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost numeric NOT NULL DEFAULT 0,
    price numeric,
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
    reorder_quantity integer,
    lead_time_days integer,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL,
    CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;


-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sale_number text NOT NULL,
    customer_name text,
    customer_email text,
    total_amount numeric NOT NULL,
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    external_id text,
    customer_id uuid,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT sales_company_id_external_id_key UNIQUE (company_id, external_id)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL,
    cost_at_time numeric,
    company_id uuid NOT NULL,
    product_id uuid,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;


-- Inventory Ledger Table
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;


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
    CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;


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
    CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;


-- Integrations Table
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    access_token text, -- Legacy, to be removed. Secrets are in Vault.
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;


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
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;

-- Sync State for Resumable Syncs
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamp with time zone,
    CONSTRAINT sync_state_pkey PRIMARY KEY (integration_id, sync_type),
    CONSTRAINT sync_state_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;


-- Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    company_id uuid,
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Export Jobs Table for Background Processing
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
    CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Webhook Log Table
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform text NOT NULL,
    webhook_id text NOT NULL,
    received_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT webhook_events_platform_webhook_id_key UNIQUE (platform, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;


-- =================================================================
-- 3. Create Indexes for Performance
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(deleted_at);
CREATE INDEX IF NOT EXISTS idx_inventory_last_sold_date ON public.inventory(last_sold_date);

-- =================================================================
-- 4. Create Database Functions
-- =================================================================

-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
  v_company_name text;
BEGIN
  -- Extract company name from metadata, default if not provided
  v_company_name := NEW.raw_app_meta_data->>'company_name';
  IF v_company_name IS NULL OR v_company_name = '' THEN
    v_company_name := NEW.email || '''s Company';
  END IF;

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (v_company_name)
  RETURNING id INTO v_company_id;

  -- Insert a corresponding record into the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, v_company_id, NEW.email, 'Owner');

  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id, 'role', 'Owner')
  WHERE id = NEW.id;
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (v_company_id);

  RETURN NEW;
END;
$$;

-- Trigger for new user function
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Migration step to ensure product_id is set on sale_items
-- This is now done manually or via a one-time script in a real migration.
-- Making product_id NOT NULL and removing sku is the final state.
-- Adding a check to see if the column exists before altering
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='sale_items' AND column_name='sku') THEN
        -- Only run this if the 'sku' column still exists, indicating the migration hasn't been fully completed.
        -- Backfill product_id from sku for any legacy records
        UPDATE public.sale_items si
        SET product_id = i.id
        FROM public.inventory i
        WHERE si.sku = i.sku
          AND si.company_id = i.company_id
          AND si.product_id IS NULL; -- Only update where it's not already set
    END IF;
EXCEPTION
    WHEN undefined_column THEN
        -- This is expected if the 'sku' column has already been dropped.
        RAISE NOTICE 'Column "sku" not found in "sale_items", skipping backfill.';
END
$$;

-- After backfill, alter the column to be NOT NULL if it exists
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_name='sale_items' AND column_name='product_id') THEN
        ALTER TABLE public.sale_items ALTER COLUMN product_id SET NOT NULL;
    END IF;
END
$$;

-- Finally, drop the redundant SKU column if it exists
ALTER TABLE public.sale_items DROP COLUMN IF EXISTS sku;


-- Drop the old function signature if it exists, to prevent the error you saw.
DROP FUNCTION IF EXISTS public.record_sale_transaction(uuid,uuid,jsonb,text,text,text,text);
DROP FUNCTION IF EXISTS public.record_sale_transaction_v2(uuid,uuid,jsonb,text,text,text,text,text);


-- Updated function to record a sale transaction
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_external_id text
) RETURNS public.sales AS $$
DECLARE
    v_sale_id uuid;
    v_customer_id uuid;
    v_sale_number text;
    v_total_amount numeric := 0;
    v_item RECORD;
    v_product_cost numeric;
    v_new_quantity integer;
    v_sale_record public.sales;
BEGIN
    -- If an external ID is provided, check if the sale already exists
    IF p_external_id IS NOT NULL THEN
        SELECT id INTO v_sale_id FROM public.sales
        WHERE company_id = p_company_id AND external_id = p_external_id;

        IF v_sale_id IS NOT NULL THEN
            RAISE NOTICE 'Sale with external ID % already exists. Skipping.', p_external_id;
            SELECT * INTO v_sale_record FROM public.sales WHERE id = v_sale_id;
            RETURN v_sale_record;
        END IF;
    END IF;

    -- Upsert customer and get ID
    IF p_customer_email IS NOT NULL AND p_customer_email <> '' THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO v_customer_id;
    END IF;

    -- Calculate total sale amount
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price numeric)
    LOOP
        v_total_amount := v_total_amount + (v_item.quantity * v_item.unit_price);
    END LOOP;

    -- Create a unique sale number
    v_sale_number := 'SALE-' || to_char(now(), 'YYYYMMDD') || '-' || (
        SELECT to_char(count(*) + 1, 'FM0000') FROM public.sales WHERE created_at::date = current_date
    );

    -- Insert the sale record
    INSERT INTO public.sales (
        company_id, customer_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id
    ) VALUES (
        p_company_id, v_customer_id, v_sale_number, p_customer_name, p_customer_email, v_total_amount, p_payment_method, p_notes, p_external_id
    ) RETURNING id INTO v_sale_id;
    
    -- Process each item in the sale
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity integer, unit_price numeric, product_name text)
    LOOP
        -- Get current product cost for the sale item record
        SELECT cost INTO v_product_cost FROM public.inventory WHERE id = v_item.product_id;
        
        -- Insert sale item
        INSERT INTO public.sale_items (
            sale_id, company_id, product_id, quantity, unit_price, product_name, cost_at_time
        ) VALUES (
            v_sale_id, p_company_id, v_item.product_id, v_item.quantity, v_item.unit_price, v_item.product_name, v_product_cost
        );
        
        -- Update inventory quantity and get the new quantity atomically
        UPDATE public.inventory
        SET quantity = quantity - v_item.quantity,
            last_sold_date = CURRENT_DATE,
            updated_at = NOW()
        WHERE id = v_item.product_id
        RETURNING quantity INTO v_new_quantity;
        
        -- Record in inventory ledger
        INSERT INTO public.inventory_ledger (
            company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes
        ) VALUES (
            p_company_id, v_item.product_id, 'sale', -v_item.quantity, v_new_quantity, v_sale_id, 'Sale #' || v_sale_number
        );
    END LOOP;

    -- Update customer stats if customer exists
    IF v_customer_id IS NOT NULL THEN
        UPDATE public.customers
        SET total_orders = total_orders + 1,
            total_spent = total_spent + v_total_amount,
            first_order_date = LEAST(first_order_date, current_date)
        WHERE id = v_customer_id;
    END IF;

    -- Return the created sale record
    SELECT * INTO v_sale_record FROM public.sales WHERE id = v_sale_id;
    RETURN v_sale_record;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;



-- =================================================================
-- 5. Define Row-Level Security (RLS) Policies
-- =================================================================
CREATE OR REPLACE FUNCTION is_member_of_company(p_company_id uuid)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id AND deleted_at IS NULL
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Helper function to get the role of the current user for their company
CREATE OR REPLACE FUNCTION get_my_role(p_company_id uuid)
RETURNS user_role AS $$
DECLARE
    v_role user_role;
BEGIN
    SELECT role INTO v_role FROM public.users
    WHERE id = auth.uid() AND company_id = p_company_id AND deleted_at IS NULL;
    RETURN v_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- Policies for 'companies' table
DROP POLICY IF EXISTS "Allow read access to company members" ON public.companies;
CREATE POLICY "Allow read access to company members" ON public.companies FOR SELECT
USING (is_member_of_company(id));

-- Policies for 'users' table
DROP POLICY IF EXISTS "Allow users to view members of their own company" ON public.users;
CREATE POLICY "Allow users to view members of their own company" ON public.users FOR SELECT
USING (is_member_of_company(company_id));

-- Policies for 'company_settings' table
DROP POLICY IF EXISTS "Allow members to read their company settings" ON public.company_settings;
CREATE POLICY "Allow members to read their company settings" ON public.company_settings FOR SELECT
USING (is_member_of_company(company_id));

DROP POLICY IF EXISTS "Allow admin/owner to update their company settings" ON public.company_settings;
CREATE POLICY "Allow admin/owner to update their company settings" ON public.company_settings FOR UPDATE
USING (is_member_of_company(company_id) AND get_my_role(company_id) IN ('Admin', 'Owner'))
WITH CHECK (is_member_of_company(company_id) AND get_my_role(company_id) IN ('Admin', 'Owner'));

-- Generic "allow all for members" policies for other tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name IN (
            'suppliers', 'inventory', 'customers', 'sales', 'sale_items', 'inventory_ledger',
            'conversations', 'messages', 'integrations', 'sync_logs', 'sync_state',
            'audit_log', 'export_jobs', 'channel_fees', 'webhook_events'
        )
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS "Allow full access for company members" ON public.%I', t_name);
        EXECUTE format(
            'CREATE POLICY "Allow full access for company members" ON public.%I FOR ALL ' ||
            'USING (is_member_of_company(company_id)) ' ||
            'WITH CHECK (is_member_of_company(company_id))',
            t_name
        );
    END LOOP;
END;
$$;


-- =================================================================
-- 6. Grant Usage on Schema and Tables
-- =================================================================
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
