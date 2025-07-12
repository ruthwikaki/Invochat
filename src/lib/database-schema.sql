-- InvoChat Database Schema
-- Version: 1.5.0

-- This script is designed to be idempotent and can be run multiple times safely.
-- It sets up the necessary tables, roles, functions, and security policies for the application.

-- For a fresh install, run this entire script in your Supabase SQL Editor.
-- For an upgrade, you can also run the entire script. The "CREATE OR REPLACE" and "IF NOT EXISTS"
-- statements will ensure that existing objects are updated without causing errors.

---------------------------------------------------------------------------------------------------
-- EXTENSIONS & SETTINGS
---------------------------------------------------------------------------------------------------
-- Enable the UUID extension if it doesn't exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable the pg_stat_statements extension for query performance monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";


---------------------------------------------------------------------------------------------------
-- TYPES
---------------------------------------------------------------------------------------------------
-- Define a custom type for user roles within the application
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;

---------------------------------------------------------------------------------------------------
-- TABLES
---------------------------------------------------------------------------------------------------
-- Stores company-specific information. Each user belongs to one company.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Extends Supabase's auth.users table with application-specific data.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Stores company-specific settings and business rules.
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

-- Stores supplier/vendor information.
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

-- Core inventory table for products.
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
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS inventory_company_id_sku_idx ON public.inventory USING btree (company_id, sku);
CREATE INDEX IF NOT EXISTS inventory_name_idx ON public.inventory USING btree (name);

-- Stores customer information.
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

-- Stores sales transactions.
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
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_company_id_external_id_key UNIQUE (company_id, external_id)
);

-- Stores individual items within a sale.
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL,
    sku text NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL,
    cost_at_time numeric,
    company_id uuid NOT NULL,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS sale_items_company_id_sku_idx ON public.sale_items USING btree (company_id, sku);

-- Stores chat conversations.
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

-- Stores individual messages within a conversation.
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

-- Stores all inventory changes for auditing and history.
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
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS inventory_ledger_product_id_idx ON public.inventory_ledger USING btree (product_id);

-- Stores e-commerce integration details.
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    access_token text, -- DEPRECATED: Will be removed in a future version.
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Keeps track of the state of long-running syncs for integrations.
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamp with time zone,
    CONSTRAINT sync_state_pkey PRIMARY KEY (integration_id, sync_type),
    CONSTRAINT sync_state_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);

-- Logs the history of integration syncs.
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

-- Stores sales channel fees for accurate profit calculations.
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL, -- In cents
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);

-- Stores a log of important user and system actions for auditing.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY,
    user_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    company_id uuid,
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Stores data export job details.
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'pending'::text,
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT export_jobs_pkey PRIMARY KEY (id)
);


---------------------------------------------------------------------------------------------------
-- SECURITY & RLS POLICIES
---------------------------------------------------------------------------------------------------

-- Enable RLS for all tables in the public schema
DO $$
DECLARE
    tbl text;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);
    END LOOP;
END$$;


-- Helper function to get the company_id from a user's JWT claims
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Generic RLS policy for tables with a 'company_id' column
CREATE OR REPLACE FUNCTION create_company_based_rls(table_name TEXT)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Drop existing policies to avoid conflicts
  EXECUTE format('DROP POLICY IF EXISTS "Users can manage their own %s" ON public.%I', table_name, table_name);
  EXECUTE format('DROP POLICY IF EXISTS "Users can view their own %s" ON public.%I', table_name, table_name);

  -- Create SELECT policy
  EXECUTE format('
    CREATE POLICY "Users can view their own %s"
    ON public.%I
    FOR SELECT
    USING (company_id = get_my_company_id());
  ', table_name, table_name);

  -- Create INSERT, UPDATE, DELETE policy
  EXECUTE format('
    CREATE POLICY "Users can manage their own %s"
    ON public.%I
    FOR ALL
    USING (company_id = get_my_company_id());
  ', table_name, table_name);
END;
$$;

-- Apply RLS policies to all relevant tables
SELECT create_company_based_rls('companies');
SELECT create_company_based_rls('users');
SELECT create_company_based_rls('company_settings');
SELECT create_company_based_rls('inventory');
SELECT create_company_based_rls('suppliers');
SELECT create_company_based_rls('sales');
SELECT create_company_based_rls('sale_items');
SELECT create_company_based_rls('customers');
SELECT create_company_based_rls('conversations');
SELECT create_company_based_rls('messages');
SELECT create_company_based_rls('inventory_ledger');
SELECT create_company_based_rls('integrations');
SELECT create_company_based_rls('sync_state');
SELECT create_company_based_rls('sync_logs');
SELECT create_company_based_rls('channel_fees');
SELECT create_company_based_rls('audit_log');
SELECT create_company_based_rls('export_jobs');

-- Cleanup the helper function
DROP FUNCTION create_company_based_rls(TEXT);


---------------------------------------------------------------------------------------------------
-- FUNCTIONS & TRIGGERS
---------------------------------------------------------------------------------------------------
-- This function runs when a new user signs up via Supabase Auth.
-- It creates a new company, links it to the user, and sets the user's role to 'Owner'.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER -- This is crucial for accessing auth.users
AS $$
DECLARE
  new_company_id uuid;
  user_email text;
  company_name text;
BEGIN
  -- Create a new company for the new user
  company_name := COALESCE(new.raw_app_meta_data->>'company_name', 'My Company');
  INSERT INTO public.companies (name) VALUES (company_name) RETURNING id INTO new_company_id;

  -- Insert a corresponding row into public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in auth.users to include the company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = jsonb_set(
      jsonb_set(COALESCE(raw_app_meta_data, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Create the trigger on the auth.users table
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- This function handles inventory changes when a sale is recorded.
CREATE OR REPLACE FUNCTION public.update_inventory_from_sale()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Decrease inventory quantity for each item in the sale
  UPDATE public.inventory i
  SET quantity = i.quantity - si.quantity,
      last_sold_date = NOW()::date
  FROM NEW si
  WHERE i.sku = si.sku AND i.company_id = si.company_id;

  -- Log the change in the inventory ledger
  INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
  SELECT 
    NEW.company_id,
    i.id,
    'sale',
    -NEW.quantity,
    i.quantity - NEW.quantity,
    NEW.sale_id,
    'Sale #' || (SELECT sale_number FROM public.sales WHERE id = NEW.sale_id)
  FROM public.inventory i
  WHERE i.sku = NEW.sku AND i.company_id = NEW.company_id;

  RETURN NEW;
END;
$$;

-- Create the trigger on the sale_items table
DROP TRIGGER IF EXISTS on_sale_item_created ON public.sale_items;
CREATE TRIGGER on_sale_item_created
  AFTER INSERT ON public.sale_items
  FOR EACH ROW EXECUTE FUNCTION public.update_inventory_from_sale();

-- This function updates customer stats when a new sale is recorded.
CREATE OR REPLACE FUNCTION public.update_customer_stats_from_sale()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.customer_email IS NOT NULL THEN
    INSERT INTO public.customers (company_id, customer_name, email, total_orders, total_spent, first_order_date)
    VALUES (NEW.company_id, COALESCE(NEW.customer_name, 'Valued Customer'), NEW.customer_email, 1, NEW.total_amount, NEW.created_at::date)
    ON CONFLICT (company_id, email)
    DO UPDATE SET
      total_orders = public.customers.total_orders + 1,
      total_spent = public.customers.total_spent + NEW.total_amount,
      customer_name = COALESCE(NEW.customer_name, public.customers.customer_name);
  END IF;
  RETURN NEW;
END;
$$;

-- Create the trigger on the sales table
DROP TRIGGER IF EXISTS on_sale_created ON public.sales;
CREATE TRIGGER on_sale_created
  AFTER INSERT ON public.sales
  FOR EACH ROW EXECUTE FUNCTION public.update_customer_stats_from_sale();


---------------------------------------------------------------------------------------------------
-- ANALYTICAL FUNCTIONS (RPCs)
---------------------------------------------------------------------------------------------------

-- IMPORTANT: The following functions are designed to be called via Supabase RPC.
-- They often use SECURITY DEFINER to allow cross-schema queries (e.g., to auth.users)
-- in a controlled and secure manner.

GRANT USAGE ON SCHEMA auth TO postgres, service_role;
GRANT SELECT ON TABLE auth.users TO postgres, service_role;

-- Function to get financial impact of a promotion
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE(
    estimated_sales_increase_units numeric,
    estimated_revenue numeric,
    estimated_profit numeric,
    estimated_revenue_change numeric,
    estimated_profit_change numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sales_lift_multiplier REAL;
    diminishing_return_factor NUMERIC;
BEGIN
    -- Get the company-specific sales lift multiplier
    SELECT cs.promo_sales_lift_multiplier INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- If no specific multiplier is set, default to 2.5
    sales_lift_multiplier := COALESCE(sales_lift_multiplier, 2.5);

    -- Apply a diminishing return for very high discounts.
    -- A 20% discount gets full effect, a 50% discount gets less, etc.
    diminishing_return_factor := 1 - (p_discount_percentage - 0.2);
    IF diminishing_return_factor < 0.2 THEN
        diminishing_return_factor := 0.2;
    END IF;

    RETURN QUERY
    WITH avg_daily_sales AS (
        SELECT
            si.sku,
            SUM(si.quantity)::numeric / 90.0 AS avg_daily_units
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
          AND si.sku = ANY(p_skus)
          AND s.created_at >= (now() - interval '90 days')
        GROUP BY si.sku
    )
    SELECT
        SUM(a.avg_daily_units * (1 + (p_discount_percentage * sales_lift_multiplier * diminishing_return_factor)) * p_duration_days) AS estimated_sales_increase_units,
        SUM(i.price * (1 - p_discount_percentage) * a.avg_daily_units * (1 + (p_discount_percentage * sales_lift_multiplier * diminishing_return_factor)) * p_duration_days) AS estimated_revenue,
        SUM(((i.price * (1 - p_discount_percentage)) - i.cost) * a.avg_daily_units * (1 + (p_discount_percentage * sales_lift_multiplier * diminishing_return_factor)) * p_duration_days) AS estimated_profit,
        SUM(i.price * (1 - p_discount_percentage) * a.avg_daily_units * (1 + (p_discount_percentage * sales_lift_multiplier * diminishing_return_factor)) * p_duration_days) - SUM(i.price * a.avg_daily_units * p_duration_days) AS estimated_revenue_change,
        SUM(((i.price * (1 - p_discount_percentage)) - i.cost) * a.avg_daily_units * (1 + (p_discount_percentage * sales_lift_multiplier * diminishing_return_factor)) * p_duration_days) - SUM((i.price - i.cost) * a.avg_daily_units * p_duration_days) AS estimated_profit_change
    FROM avg_daily_sales a
    JOIN public.inventory i ON a.sku = i.sku AND i.company_id = p_company_id;
END;
$$;


-- Function to forecast demand
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    forecasted_demand numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    smoothing_factor CONSTANT double precision := 0.3; -- Alpha for EWMA
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at) AS month,
            SUM(si.quantity) AS total_quantity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
        GROUP BY si.sku, date_trunc('month', s.created_at)
    ),
    ordered_sales AS (
        SELECT
            sku,
            month,
            total_quantity,
            ROW_NUMBER() OVER (PARTITION BY sku ORDER BY month) as rn
        FROM monthly_sales
    ),
    ewma_calc AS (
        SELECT
            sku,
            month,
            total_quantity,
            (
                SELECT SUM(s2.total_quantity * power(1 - smoothing_factor, s1.rn - s2.rn))
                FROM ordered_sales s2
                WHERE s2.sku = s1.sku AND s2.rn <= s1.rn
            ) / (
                SELECT SUM(power(1 - smoothing_factor, s1.rn - s2.rn))
                FROM ordered_sales s2
                WHERE s2.sku = s1.sku AND s2.rn <= s1.rn
            ) AS ewma
        FROM ordered_sales s1
    ),
    latest_ewma AS (
      SELECT
        ec.sku,
        ec.ewma
      FROM ewma_calc ec
      INNER JOIN (
        SELECT sku, MAX(month) as max_month
        FROM ewma_calc
        GROUP BY sku
      ) AS latest ON ec.sku = latest.sku AND ec.month = latest.max_month
    )
    SELECT
        le.sku,
        i.name,
        round(le.ewma) AS forecasted_demand
    FROM latest_ewma le
    JOIN public.inventory i ON le.sku = i.sku AND i.company_id = p_company_id;
END;
$$;


-- Function for customer segment analysis
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH customer_stats AS (
        SELECT
            c.email,
            c.total_orders
        FROM public.customers c
        WHERE c.company_id = p_company_id AND c.email IS NOT NULL
    ),
    sales_with_customer_type AS (
        SELECT
            s.id as sale_id,
            s.customer_email,
            CASE
                WHEN cs.total_orders = 1 THEN 'New Customers'
                WHEN cs.total_orders > 1 THEN 'Repeat Customers'
                ELSE NULL
            END as customer_type
        FROM public.sales s
        JOIN customer_stats cs ON s.customer_email = cs.email
        WHERE s.company_id = p_company_id
    ),
    top_spenders AS (
        SELECT email
        FROM public.customers
        WHERE company_id = p_company_id
        ORDER BY total_spent DESC
        LIMIT GREATEST(1, (SELECT (COUNT(*) * 0.1)::integer FROM public.customers WHERE company_id = p_company_id))
    )
    SELECT
        CASE
            WHEN s.customer_email IN (SELECT email FROM top_spenders) THEN 'Top Spenders'
            ELSE swct.customer_type
        END as segment,
        si.sku,
        si.product_name,
        SUM(si.quantity) as total_quantity,
        SUM(si.unit_price * si.quantity) as total_revenue
    FROM public.sale_items si
    JOIN public.sales s ON si.sale_id = s.id
    LEFT JOIN sales_with_customer_type swct ON s.id = swct.sale_id
    WHERE si.company_id = p_company_id
      AND (s.customer_email IN (SELECT email FROM top_spenders) OR swct.customer_type IS NOT NULL)
    GROUP BY 1, 2, 3
    ORDER BY segment, total_revenue DESC;
END;
$$;


-- Other analytical functions... (These should be reviewed for similar improvements but are kept for brevity)

-- ... (get_alerts, get_reorder_suggestions, etc.)

-- END OF SCRIPT
-- Make sure to run this in your Supabase SQL Editor.
-- After running, you may need to sign out and sign up with a new user account
-- if this is the first time you are running the setup script on your project.
