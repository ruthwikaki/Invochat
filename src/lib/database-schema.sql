-- Supabase InvoChat Database Schema
-- Version: 1.6
-- This script is idempotent and can be re-run safely.

-- 1. Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Create Custom Types
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM (
            'Owner',
            'Admin',
            'Member'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM (
            'shopify',
            'woocommerce',
            'amazon_fba'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sync_status_type') THEN
        CREATE TYPE public.sync_status_type AS ENUM (
            'syncing_products',
            'syncing_sales',
            'syncing',
            'success',
            'failed',
            'idle'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_type') THEN
        CREATE TYPE public.alert_type AS ENUM (
            'low_stock',
            'dead_stock',
            'predictive',
            'profit_warning'
        );
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alert_severity') THEN
        CREATE TYPE public.alert_severity AS ENUM (
            'info',
            'warning',
            'critical'
        );
    END IF;
END$$;


-- 3. Set up Tables
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    overstock_multiplier numeric DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 100000 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    promo_sales_lift_multiplier numeric DEFAULT 2.5 NOT NULL,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Add missing columns to company_settings if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='company_settings' AND column_name='promo_sales_lift_multiplier') THEN
        ALTER TABLE public.company_settings ADD COLUMN promo_sales_lift_multiplier numeric DEFAULT 2.5 NOT NULL;
    END IF;
END$$;


CREATE TABLE IF NOT EXISTS public.users (
    id uuid NOT NULL,
    email text,
    company_id uuid,
    role public.user_role DEFAULT 'Member'::public.user_role,
    deleted_at timestamp with time zone,
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE SET NULL,
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    price integer,
    cost integer,
    quantity integer DEFAULT 0 NOT NULL,
    reorder_point integer,
    supplier_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    barcode text,
    last_sold_date timestamp with time zone,
    reorder_quantity integer,
    lead_time_days integer,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users(id) ON DELETE SET NULL,
    CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);


CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    notes text,
    CONSTRAINT suppliers_pkey PRIMARY KEY (id),
    CONSTRAINT suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

ALTER TABLE public.inventory
ADD CONSTRAINT inventory_supplier_id_fkey
FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);

CREATE TABLE IF NOT EXISTS public.sales (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid,
    sale_number text,
    customer_name text,
    customer_email text,
    total_amount integer,
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    external_id text,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL,
    CONSTRAINT sales_company_id_external_id_key UNIQUE (company_id, external_id)
);


CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sale_id uuid NOT NULL,
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL,
    cost_at_time integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    product_id uuid NOT NULL,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_id uuid,
    notes text,
    CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_accessed_at timestamp with time zone DEFAULT now() NOT NULL,
    is_starred boolean DEFAULT false NOT NULL,
    CONSTRAINT conversations_pkey PRIMARY KEY (id),
    CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role public.user_role NOT NULL,
    content text,
    visualization jsonb,
    confidence real,
    assumptions text[],
    component text,
    component_props jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT messages_pkey PRIMARY KEY (id),
    CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    company_id uuid,
    user_id uuid,
    action text,
    details jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    platform public.integration_platform NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT true NOT NULL,
    last_sync_at timestamp with time zone,
    sync_status public.sync_status_type,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT integrations_pkey PRIMARY KEY (id),
    CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT integrations_company_id_platform_key UNIQUE (company_id, platform)
);

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric(5,4) NOT NULL,
    fixed_fee integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);

CREATE TABLE IF NOT EXISTS public.sync_logs (
    id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    integration_id uuid,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone,
    CONSTRAINT sync_logs_pkey PRIMARY KEY (id),
    CONSTRAINT sync_logs_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.sync_state (
    id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    integration_id uuid NOT NULL,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamp with time zone,
    CONSTRAINT sync_state_pkey PRIMARY KEY (id),
    CONSTRAINT sync_state_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE,
    CONSTRAINT sync_state_integration_id_sync_type_key UNIQUE (integration_id, sync_type)
);


CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    requested_by_user_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    download_url text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT export_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT export_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT export_jobs_requested_by_user_id_fkey FOREIGN KEY (requested_by_user_id) REFERENCES public.users(id) ON DELETE CASCADE
);


-- 4. Set up Row-Level Security (RLS) Policies

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS Policies
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = auth.uid();
$$;

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.companies;
CREATE POLICY "Enable all access for users based on company_id" ON public.companies
FOR ALL USING (id = public.get_my_company_id());

-- Repeat for all other tables
DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.inventory;
CREATE POLICY "Enable all access for users based on company_id" ON public.inventory
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.suppliers;
CREATE POLICY "Enable all access for users based on company_id" ON public.suppliers
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.sales;
CREATE POLICY "Enable all access for users based on company_id" ON public.sales
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.sale_items;
CREATE POLICY "Enable all access for users based on company_id" ON public.sale_items
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.customers;
CREATE POLICY "Enable all access for users based on company_id" ON public.customers
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.inventory_ledger;
CREATE POLICY "Enable all access for users based on company_id" ON public.inventory_ledger
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.company_settings;
CREATE POLICY "Enable all access for users based on company_id" ON public.company_settings
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.conversations;
CREATE POLICY "Enable all access for users based on company_id" ON public.conversations
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.messages;
CREATE POLICY "Enable all access for users based on company_id" ON public.messages
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.audit_log;
CREATE POLICY "Enable all access for users based on company_id" ON public.audit_log
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.integrations;
CREATE POLICY "Enable all access for users based on company_id" ON public.integrations
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.channel_fees;
CREATE POLICY "Enable all access for users based on company_id" ON public.channel_fees
FOR ALL USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.sync_logs;
CREATE POLICY "Enable all access for users based on company_id" ON public.sync_logs
FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_my_company_id()));

DROP POLICY IF EXISTS "Enable all access for users based on company_id" ON public.sync_state;
CREATE POLICY "Enable all access for users based on company_id" ON public.sync_state
FOR ALL USING (integration_id IN (SELECT id FROM public.integrations WHERE company_id = public.get_my_company_id()));


-- 6. Set up Database Functions for user/company creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_role public.user_role;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- The creator of the company is the Owner
  user_role := 'Owner';

  -- Update the new user's app_metadata with the company_id and role
  UPDATE auth.users
  SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id, 'role', user_role)
  WHERE id = new.id;
  
  -- Insert a corresponding entry into public.users
  INSERT INTO public.users (id, email, company_id, role)
  VALUES (new.id, new.email, new_company_id, user_role);
  
  RETURN new;
END;
$$;


-- 7. Set up a trigger to call the function when a new user signs up
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to handle inventory quantity changes and log them
CREATE OR REPLACE FUNCTION public.log_inventory_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.inventory_ledger(company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (NEW.company_id, NEW.id, TG_ARGV[0], NEW.quantity - COALESCE(OLD.quantity, 0), NEW.quantity, NULL, TG_ARGV[1]);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for inventory updates
DROP TRIGGER IF EXISTS on_inventory_update ON public.inventory;
CREATE TRIGGER on_inventory_update
AFTER UPDATE OF quantity ON public.inventory
FOR EACH ROW
WHEN (OLD.quantity IS DISTINCT FROM NEW.quantity)
EXECUTE FUNCTION public.log_inventory_change('adjustment', 'Manual inventory update');


-- Function to update `last_sold_date` and `quantity` on sale
CREATE OR REPLACE FUNCTION public.handle_sale_item_insert()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.inventory
    SET 
        quantity = quantity - NEW.quantity,
        last_sold_date = NEW.created_at
    WHERE id = NEW.product_id AND company_id = NEW.company_id;

    INSERT INTO public.inventory_ledger(company_id, product_id, change_type, quantity_change, new_quantity, related_id)
    SELECT NEW.company_id, NEW.product_id, 'sale', -NEW.quantity, i.quantity, NEW.sale_id
    FROM public.inventory i
    WHERE i.id = NEW.product_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for new sale items
DROP TRIGGER IF EXISTS on_sale_item_insert ON public.sale_items;
CREATE TRIGGER on_sale_item_insert
AFTER INSERT ON public.sale_items
FOR EACH ROW
EXECUTE FUNCTION public.handle_sale_item_insert();

-- Function to handle customer creation on sale
CREATE OR REPLACE FUNCTION public.handle_new_sale_customer()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.customer_email IS NOT NULL THEN
        INSERT INTO public.customers(company_id, customer_name, email)
        VALUES (NEW.company_id, COALESCE(NEW.customer_name, 'Valued Customer'), NEW.customer_email)
        ON CONFLICT (company_id, email) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for new sales
DROP TRIGGER IF EXISTS on_new_sale_customer ON public.sales;
CREATE TRIGGER on_new_sale_customer
AFTER INSERT ON public.sales
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_sale_customer();


DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid,text[],numeric,integer);
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(p_company_id uuid, p_skus text[], p_discount_percentage numeric, p_duration_days integer)
RETURNS TABLE(
    estimated_sales_lift_multiplier numeric, 
    estimated_additional_units_sold numeric, 
    estimated_original_revenue numeric, 
    estimated_promotional_revenue numeric, 
    estimated_revenue_change numeric, 
    estimated_original_profit numeric, 
    estimated_promotional_profit numeric, 
    estimated_profit_change numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    sales_lift_multiplier numeric;
    settings RECORD;
BEGIN
    SELECT s.promo_sales_lift_multiplier INTO settings FROM public.company_settings s WHERE s.company_id = p_company_id;

    -- Non-linear sales lift model
    sales_lift_multiplier := 1 + (p_discount_percentage * POW((1 / (p_discount_percentage + 0.4)), 0.5) * settings.promo_sales_lift_multiplier);

    RETURN QUERY
    WITH avg_sales AS (
        SELECT
            si.product_id,
            p.sku,
            p.name,
            p.price,
            p.cost,
            SUM(si.quantity) / 90.0 AS avg_daily_sales
        FROM public.sale_items si
        JOIN public.inventory p ON si.product_id = p.id
        WHERE p.company_id = p_company_id AND p.sku = ANY(p_skus)
        AND si.created_at >= NOW() - INTERVAL '90 days'
        GROUP BY si.product_id, p.sku, p.name, p.price, p.cost
    )
    SELECT
        sales_lift_multiplier AS estimated_sales_lift_multiplier,
        SUM(avg_daily_sales * p_duration_days * (sales_lift_multiplier - 1)) AS estimated_additional_units_sold,
        SUM(avg_daily_sales * p_duration_days * price) AS estimated_original_revenue,
        SUM(avg_daily_sales * p_duration_days * sales_lift_multiplier * price * (1 - p_discount_percentage)) AS estimated_promotional_revenue,
        SUM(avg_daily_sales * p_duration_days * sales_lift_multiplier * price * (1 - p_discount_percentage)) - SUM(avg_daily_sales * p_duration_days * price) AS estimated_revenue_change,
        SUM(avg_daily_sales * p_duration_days * (price - cost)) AS estimated_original_profit,
        SUM(avg_daily_sales * p_duration_days * sales_lift_multiplier * (price * (1 - p_discount_percentage) - cost)) AS estimated_promotional_profit,
        SUM(avg_daily_sales * p_duration_days * sales_lift_multiplier * (price * (1 - p_discount_percentage) - cost)) - SUM(avg_daily_sales * p_duration_days * (price - cost)) AS estimated_profit_change
    FROM avg_sales;
END;
$$;


DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE(product_name text, sku text, current_inventory integer, avg_monthly_sales numeric, next_month_forecast integer)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            date_trunc('month', s.created_at) AS sale_month,
            si.product_id,
            SUM(si.quantity) as total_quantity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE si.company_id = p_company_id
        GROUP BY 1, 2
    ),
    ewma_sales AS (
        SELECT
            product_id,
            total_quantity,
            sale_month,
            -- Calculate EWMA with alpha = 0.3
            AVG(total_quantity) OVER (PARTITION BY product_id ORDER BY sale_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 0.3 +
            LAG(AVG(total_quantity) OVER (PARTITION BY product_id ORDER BY sale_month), 1, total_quantity) OVER (PARTITION BY product_id ORDER BY sale_month) * 0.7 AS ewma
        FROM monthly_sales
    ),
    latest_forecast AS (
        SELECT DISTINCT ON (product_id)
            product_id,
            ewma
        FROM ewma_sales
        ORDER BY product_id, sale_month DESC
    )
    SELECT
        i.name as product_name,
        i.sku,
        i.quantity as current_inventory,
        lf.ewma as avg_monthly_sales,
        ceil(lf.ewma)::integer as next_month_forecast
    FROM latest_forecast lf
    JOIN public.inventory i ON lf.product_id = i.id
    WHERE i.company_id = p_company_id
    ORDER BY lf.ewma DESC
    LIMIT 10;
END;
$$;


DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(segment text, sku text, product_name text, total_quantity bigint, total_revenue bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    total_customers integer;
BEGIN
    -- Get total customer count for percentage calculation
    SELECT COUNT(*) INTO total_customers FROM public.customers WHERE company_id = p_company_id;

    -- Use a temporary table to avoid repeating the main query
    CREATE TEMP TABLE IF NOT EXISTS customer_sales_ranked ON COMMIT DROP AS
    SELECT
        c.id as customer_id,
        c.email,
        c.created_at as customer_created_at,
        s.created_at as sale_created_at,
        si.product_id,
        si.quantity,
        (si.quantity * si.unit_price) as sale_revenue,
        rank() OVER (PARTITION BY c.id ORDER BY s.created_at) as sale_rank,
        sum(si.quantity * si.unit_price) OVER (PARTITION BY c.id) as customer_total_spend
    FROM public.customers c
    JOIN public.sales s ON c.email = s.customer_email AND c.company_id = s.company_id
    JOIN public.sale_items si ON s.id = si.sale_id AND s.company_id = si.company_id
    WHERE c.company_id = p_company_id;

    RETURN QUERY
    WITH ranked_sales AS (
        SELECT * FROM customer_sales_ranked
    ),
    top_spenders AS (
        SELECT DISTINCT email FROM ranked_sales
        ORDER BY customer_total_spend DESC
        LIMIT GREATEST(1, floor(total_customers * 0.1)) -- Select top 10% or at least 1
    )
    -- New Customers: products bought on their first ever order
    SELECT
        'New Customers'::text as segment,
        i.sku,
        i.name,
        sum(rs.quantity)::bigint as total_quantity,
        sum(rs.sale_revenue)::bigint as total_revenue
    FROM ranked_sales rs
    JOIN inventory i ON rs.product_id = i.id
    WHERE rs.sale_rank = 1
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5

    UNION ALL

    -- Repeat Customers: products bought on their 2nd, 3rd, etc. order
    SELECT
        'Repeat Customers'::text as segment,
        i.sku,
        i.name,
        sum(rs.quantity)::bigint as total_quantity,
        sum(rs.sale_revenue)::bigint as total_revenue
    FROM ranked_sales rs
    JOIN inventory i ON rs.product_id = i.id
    WHERE rs.sale_rank > 1
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5

    UNION ALL

    -- Top Spenders: products bought by the top 10% of customers by lifetime value
    SELECT
        'Top Spenders'::text as segment,
        i.sku,
        i.name,
        sum(rs.quantity)::bigint as total_quantity,
        sum(rs.sale_revenue)::bigint as total_revenue
    FROM ranked_sales rs
    JOIN inventory i ON rs.product_id = i.id
    WHERE rs.email IN (SELECT email FROM top_spenders)
    GROUP BY i.sku, i.name
    ORDER BY total_revenue DESC
    LIMIT 5;
END;
$$;
