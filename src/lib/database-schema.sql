-- ----------------------------------------------------------------------------------
--
-- InvoChat - Conversational Inventory Intelligence
--
-- This script sets up the necessary database schema, tables, functions, and
-- security policies for the InvoChat application to function correctly.
--
-- To use this script:
-- 1. Navigate to the "SQL Editor" in your Supabase project dashboard.
-- 2. Click "New query".
-- 3. Copy the ENTIRE contents of this file and paste it into the editor.
-- 4. Click "Run".
--
-- After running the script successfully, you must sign up for a new user account
-- in the application. This new account will be correctly configured by the
-- `handle_new_user` trigger defined below.
--
-- ----------------------------------------------------------------------------------


-- ----------------------------------------------------------------------------------
-- EXTENSIONS & TYPES
-- ----------------------------------------------------------------------------------

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define a custom user role type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- ----------------------------------------------------------------------------------
-- TABLE: companies
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- ----------------------------------------------------------------------------------
-- TABLE: users
-- ----------------------------------------------------------------------------------
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
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to see their own company's users" ON public.users FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.company_id = public.users.company_id));


-- ----------------------------------------------------------------------------------
-- TABLE: company_settings
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 100000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage settings for their own company" ON public.company_settings FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.company_settings.company_id));

-- ----------------------------------------------------------------------------------
-- TABLE: suppliers
-- ----------------------------------------------------------------------------------
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
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage suppliers for their own company" ON public.suppliers FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.suppliers.company_id));


-- ----------------------------------------------------------------------------------
-- TABLE: inventory
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost integer NOT NULL DEFAULT 0,
    price integer,
    reorder_point integer,
    reorder_quantity integer,
    last_sold_date date,
    barcode text,
    supplier_id uuid,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL,
    CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage inventory for their own company" ON public.inventory FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.inventory.company_id));
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);


-- ----------------------------------------------------------------------------------
-- TABLE: inventory_ledger
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
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
CREATE POLICY "Allow users to see ledger for their own company" ON public.inventory_ledger FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.inventory_ledger.company_id));


-- ----------------------------------------------------------------------------------
-- TABLE: customers
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    customer_name text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now(),
    deleted_at timestamp with time zone,
    CONSTRAINT customers_pkey PRIMARY KEY (id),
    CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT customers_company_id_email_key UNIQUE (company_id, email)
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage customers for their own company" ON public.customers FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.customers.company_id));

-- ----------------------------------------------------------------------------------
-- TABLE: sales & sale_items
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sale_number text NOT NULL,
    customer_id uuid,
    total_amount integer NOT NULL, -- in cents
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    external_id text,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage sales for their own company" ON public.sales FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.sales.company_id));


CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- in cents
    cost_at_time integer, -- in cents
    company_id uuid NOT NULL,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT,
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage sale_items for their own company" ON public.sale_items FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.sale_items.company_id));


-- ----------------------------------------------------------------------------------
-- TABLE: integrations
-- ----------------------------------------------------------------------------------
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
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage integrations for their own company" ON public.integrations FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.integrations.company_id));


-- ----------------------------------------------------------------------------------
-- TABLE: channel_fees
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee integer NOT NULL, -- in cents
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT channel_fees_pkey PRIMARY KEY (id),
    CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE (company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage channel fees for their company" ON public.channel_fees FOR ALL USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.channel_fees.company_id));

-- ----------------------------------------------------------------------------------
-- Other Tables (conversations, messages, etc.)
-- ----------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  company_id uuid NOT NULL,
  title text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  last_accessed_at timestamp with time zone DEFAULT now(),
  is_starred boolean DEFAULT false,
  CONSTRAINT conversations_pkey PRIMARY KEY (id),
  CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage their own conversations" ON public.conversations FOR ALL USING (user_id = auth.uid());


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
  CONSTRAINT messages_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow users to manage messages in their own conversations" ON public.messages FOR ALL USING (auth.uid() IN (SELECT user_id FROM conversations WHERE id = public.messages.conversation_id));

-- ----------------------------------------------------------------------------------
-- VIEWS
-- ----------------------------------------------------------------------------------
DROP VIEW IF EXISTS public.inventory_view;
CREATE OR REPLACE VIEW public.inventory_view AS
SELECT
    i.id as product_id,
    i.company_id,
    i.sku,
    i.name as product_name,
    i.category,
    i.quantity,
    i.cost,
    i.price,
    (i.quantity * i.cost) as total_value,
    i.reorder_point,
    s.name as supplier_name,
    s.id as supplier_id,
    i.barcode
FROM
    public.inventory i
LEFT JOIN
    public.suppliers s ON i.supplier_id = s.id
WHERE
    i.deleted_at IS NULL;

-- This materialized view is refreshed by a database function.
DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    c.id as company_id,
    SUM(i.quantity * i.cost) as inventory_value,
    COUNT(i.id) as total_skus,
    SUM(CASE WHEN i.quantity <= i.reorder_point THEN 1 ELSE 0 END) as low_stock_count
FROM
    public.companies c
LEFT JOIN
    public.inventory i ON c.id = i.company_id AND i.deleted_at IS NULL
GROUP BY
    c.id;

-- ----------------------------------------------------------------------------------
-- AUTH TRIGGER: handle_new_user
-- ----------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
  user_company_name text;
BEGIN
  -- Create a new company for the user
  user_company_name := COALESCE(new.raw_user_meta_data->>'company_name', new.email);
  INSERT INTO public.companies (name)
  VALUES (user_company_name)
  RETURNING id INTO new_company_id;

  -- Insert the user into the public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in the auth schema
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
  ) || jsonb_set(
      COALESCE(app_metadata, '{}'::jsonb),
      '{role}',
      to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ----------------------------------------------------------------------------------
-- HELPER & RPC FUNCTIONS
-- ----------------------------------------------------------------------------------

-- Function to refresh all materialized views for a company
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
    -- Add other views to refresh here in the future
END;
$$;


-- Function to get distinct inventory categories for a company
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT category
    FROM public.inventory
    WHERE company_id = p_company_id AND category IS NOT NULL AND deleted_at IS NULL;
$$;

-- Function to get dashboard metrics
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer DEFAULT 30)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    metrics json;
BEGIN
    SELECT json_build_object(
        'totalSalesValue', COALESCE(SUM(s.total_amount), 0),
        'totalProfit', COALESCE(SUM(si.quantity * (si.unit_price - si.cost_at_time)), 0),
        'totalOrders', COUNT(DISTINCT s.id),
        'averageOrderValue', COALESCE(AVG(s.total_amount), 0),
        'deadStockItemsCount', (SELECT COUNT(*) FROM public.inventory WHERE company_id = p_company_id AND last_sold_date < (now() - (p_days || ' days')::interval) AND deleted_at IS NULL),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', d.day, 'Sales', COALESCE(daily_sales, 0)))
            FROM (SELECT generate_series(date_trunc('day', now() - (p_days-1 || ' days')::interval), date_trunc('day', now()), '1 day'::interval)::date AS day) d
            LEFT JOIN (
                SELECT date_trunc('day', created_at)::date AS sale_day, SUM(total_amount) AS daily_sales
                FROM public.sales
                WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval
                GROUP BY 1
            ) s ON d.day = s.sale_day
        ),
        'inventoryByCategoryData', (
             SELECT json_agg(json_build_object('name', category, 'value', total_value))
             FROM (
                SELECT COALESCE(category, 'Uncategorized') as category, SUM(quantity * cost) as total_value
                FROM public.inventory
                WHERE company_id = p_company_id AND deleted_at IS NULL
                GROUP BY COALESCE(category, 'Uncategorized')
                ORDER BY total_value DESC
                LIMIT 5
             ) as cat_data
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', c.customer_name, 'value', s.total_spent))
            FROM (
                SELECT customer_id, SUM(total_amount) as total_spent
                FROM public.sales
                WHERE company_id = p_company_id AND customer_id IS NOT NULL
                GROUP BY customer_id
                ORDER BY total_spent DESC
                LIMIT 5
            ) s
            JOIN public.customers c ON s.customer_id = c.id
        )
    )
    INTO metrics
    FROM public.sales s
    LEFT JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id AND s.created_at >= now() - (p_days || ' days')::interval;

    RETURN metrics;
END;
$$;


-- =================================================================================
-- NEW ANALYTICS & REPORTING FUNCTIONS
-- =================================================================================

-- Function for Cash Flow Intelligence Page
CREATE OR REPLACE FUNCTION get_cash_flow_insights(p_company_id uuid)
RETURNS TABLE (dead_stock_value numeric, slow_mover_value numeric, dead_stock_threshold_days int)
LANGUAGE plpgsql AS $$
DECLARE
    settings_row record;
BEGIN
    SELECT cs.dead_stock_days INTO settings_row FROM company_settings cs WHERE cs.company_id = p_company_id;
    
    RETURN QUERY
    SELECT
        COALESCE(SUM(CASE WHEN i.last_sold_date < (now() - (settings_row.dead_stock_days || ' day')::interval) THEN i.quantity * i.cost ELSE 0 END), 0) / 100 AS dead_stock_value,
        COALESCE(SUM(CASE WHEN i.last_sold_date >= (now() - (settings_row.dead_stock_days || ' day')::interval) AND i.last_sold_date < (now() - '30 day'::interval) THEN i.quantity * i.cost ELSE 0 END), 0) / 100 AS slow_mover_value,
        settings_row.dead_stock_days
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL;
END;
$$;

-- Function for Product Lifecycle Analysis Report
CREATE OR REPLACE FUNCTION get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json AS $$
DECLARE
    result json;
BEGIN
    WITH product_sales_history AS (
        SELECT
            p.id as product_id,
            p.sku,
            p.name as product_name,
            p.created_at,
            MIN(s.created_at) as first_sale,
            MAX(s.created_at) as last_sale,
            SUM(si.quantity) as total_units_sold,
            SUM(si.quantity * si.unit_price) as total_revenue,
            SUM(CASE WHEN s.created_at >= (now() - '90 days'::interval) THEN si.quantity ELSE 0 END) as sales_last_90_days,
            SUM(CASE WHEN s.created_at < (now() - '90 days'::interval) AND s.created_at >= (now() - '180 days'::interval) THEN si.quantity ELSE 0 END) as sales_prev_90_days
        FROM inventory p
        JOIN sale_items si ON p.id = si.product_id
        JOIN sales s ON si.sale_id = s.id
        WHERE p.company_id = p_company_id AND p.deleted_at IS NULL
        GROUP BY p.id
    ),
    product_stages AS (
        SELECT
            *,
            CASE
                WHEN first_sale >= (now() - '60 days'::interval) THEN 'Launch'
                WHEN sales_last_90_days > (sales_prev_90_days * 1.2) AND sales_last_90_days > 10 THEN 'Growth'
                WHEN sales_last_90_days > 0 AND sales_last_90_days <= (sales_prev_90_days * 1.2) AND sales_last_90_days >= (sales_prev_90_days * 0.8) THEN 'Maturity'
                ELSE 'Decline'
            END as stage
        FROM product_sales_history
    )
    SELECT json_build_object(
        'summary', (SELECT json_build_object(
            'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
            'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
            'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
            'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
        ) FROM product_stages),
        'products', (SELECT json_agg(
            json_build_object(
                'sku', sku,
                'product_name', product_name,
                'stage', stage,
                'total_revenue', total_revenue
            ) ORDER BY total_revenue DESC
        ) FROM product_stages)
    )
    INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function for Inventory Risk Report
CREATE OR REPLACE FUNCTION get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    risk_score int,
    risk_level text,
    total_value int,
    reason text
) AS $$
BEGIN
    RETURN QUERY
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name,
            i.quantity,
            i.cost,
            COALESCE(EXTRACT(DAY FROM now() - i.last_sold_date), 999) as days_since_last_sale,
            COALESCE(i.quantity * i.cost, 0) as total_value,
            (SELECT SUM(si.quantity) FROM sale_items si JOIN sales s ON si.sale_id = s.id WHERE si.product_id = i.id AND s.created_at > now() - '90 days'::interval) as sales_last_90_days
        FROM inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
    )
    SELECT
        rf.sku,
        rf.name,
        (
            (CASE WHEN rf.days_since_last_sale > 180 THEN 40 WHEN rf.days_since_last_sale > 90 THEN 25 ELSE 0 END) +
            (CASE WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 6) THEN 30 WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 3) THEN 15 ELSE 0 END) +
            (CASE WHEN rf.total_value > 1000000 THEN 30 WHEN rf.total_value > 200000 THEN 15 ELSE 0 END)
        )::int as risk_score,
        CASE
            WHEN (
                (CASE WHEN rf.days_since_last_sale > 180 THEN 40 WHEN rf.days_since_last_sale > 90 THEN 25 ELSE 0 END) +
                (CASE WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 6) THEN 30 WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 3) THEN 15 ELSE 0 END) +
                (CASE WHEN rf.total_value > 1000000 THEN 30 WHEN rf.total_value > 200000 THEN 15 ELSE 0 END)
            ) > 75 THEN 'High'
            WHEN (
                (CASE WHEN rf.days_since_last_sale > 180 THEN 40 WHEN rf.days_since_last_sale > 90 THEN 25 ELSE 0 END) +
                (CASE WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 6) THEN 30 WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 3) THEN 15 ELSE 0 END) +
                (CASE WHEN rf.total_value > 1000000 THEN 30 WHEN rf.total_value > 200000 THEN 15 ELSE 0 END)
            ) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        rf.total_value::int,
        TRIM(BOTH ' and ' FROM
            CONCAT_WS(' and ',
                CASE WHEN rf.days_since_last_sale > 90 THEN 'Slow Moving' ELSE NULL END,
                CASE WHEN (rf.sales_last_90_days > 0 AND rf.quantity / rf.sales_last_90_days > 3) THEN 'High Stock' ELSE NULL END,
                CASE WHEN rf.total_value > 200000 THEN 'High Value' ELSE NULL END
            )
        ) as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for Customer Segment Analysis Report
CREATE OR REPLACE FUNCTION get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (segment text, sku text, product_name text, total_quantity bigint, total_revenue bigint) AS $$
BEGIN
    RETURN QUERY
    WITH customer_segments AS (
        SELECT
            c.id as customer_id,
            CASE
                WHEN s.order_count = 1 THEN 'New Customers'
                WHEN s.order_count > 1 THEN 'Repeat Customers'
            END as segment
        FROM customers c
        JOIN (SELECT customer_id, COUNT(*) as order_count FROM sales WHERE company_id = p_company_id GROUP BY customer_id) s ON c.id = s.customer_id
        WHERE c.company_id = p_company_id
        UNION ALL
        SELECT customer_id, 'Top Spenders'
        FROM (SELECT customer_id, SUM(total_amount) as total_spent FROM sales WHERE company_id = p_company_id GROUP BY customer_id ORDER BY total_spent DESC LIMIT 50) as top_spenders
    )
    SELECT
        cs.segment,
        i.sku,
        i.name as product_name,
        SUM(si.quantity) as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM sale_items si
    JOIN sales s ON si.sale_id = s.id
    JOIN inventory i ON si.product_id = i.id
    JOIN customer_segments cs ON s.customer_id = cs.customer_id
    WHERE s.company_id = p_company_id
    GROUP BY cs.segment, i.sku, i.name
    ORDER BY cs.segment, total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for Inventory Aging Report
CREATE OR REPLACE FUNCTION get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE (sku text, product_name text, quantity int, total_value int, days_since_last_sale int) AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.sku,
        i.name,
        i.quantity,
        (i.quantity * i.cost)::int as total_value,
        COALESCE(EXTRACT(DAY FROM now() - i.last_sold_date), 9999)::int as days_since_last_sale
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    ORDER BY days_since_last_sale DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for Promotional Impact Analysis
CREATE OR REPLACE FUNCTION get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days int
) RETURNS json AS $$
DECLARE
    result json;
    elasticity_factor numeric := 1.5; -- Assumption: 10% discount leads to 15% sales increase
BEGIN
    WITH promo_items AS (
        SELECT
            i.id,
            i.sku,
            i.name,
            i.cost,
            i.price,
            (SELECT SUM(si.quantity) FROM sale_items si JOIN sales s ON si.sale_id = s.id WHERE si.product_id = i.id AND s.created_at >= now() - '90 days'::interval) as sales_last_90_days
        FROM inventory i
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    ),
    analysis AS (
        SELECT
            sku,
            name,
            price,
            cost,
            sales_last_90_days / 90.0 as avg_daily_sales,
            (sales_last_90_days / 90.0) * (1 + (p_discount_percentage * elasticity_factor)) as projected_daily_sales
        FROM promo_items
    )
    SELECT json_build_object(
        'original_revenue', SUM(avg_daily_sales * price * p_duration_days),
        'original_profit', SUM(avg_daily_sales * (price - cost) * p_duration_days),
        'projected_revenue', SUM(projected_daily_sales * (price * (1 - p_discount_percentage)) * p_duration_days),
        'projected_profit', SUM(projected_daily_sales * (price * (1 - p_discount_percentage) - cost) * p_duration_days)
    )
    INTO result
    FROM analysis;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function for Profit Warning Alerts
CREATE OR REPLACE FUNCTION get_profit_warning_alerts(p_company_id uuid)
RETURNS TABLE (
    type text,
    sku text,
    product_name text,
    product_id uuid,
    current_stock int,
    reorder_point int,
    last_sold_date date,
    value numeric,
    days_of_stock_remaining numeric,
    recent_margin numeric,
    previous_margin numeric
) AS $$
BEGIN
    RETURN QUERY
    WITH recent_sales AS (
        SELECT
            si.product_id,
            AVG(si.unit_price - si.cost_at_time) / AVG(si.unit_price) as margin
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - '30 days'::interval
        GROUP BY si.product_id
    ),
    previous_sales AS (
        SELECT
            si.product_id,
            AVG(si.unit_price - si.cost_at_time) / AVG(si.unit_price) as margin
        FROM sale_items si
        JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - '90 days'::interval AND s.created_at < now() - '30 days'::interval
        GROUP BY si.product_id
    )
    SELECT
        'profit_warning'::text,
        i.sku,
        i.name,
        i.id,
        i.quantity,
        i.reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::numeric,
        NULL::numeric,
        rs.margin as recent_margin,
        ps.margin as previous_margin
    FROM inventory i
    JOIN recent_sales rs ON i.id = rs.product_id
    JOIN previous_sales ps ON i.id = ps.product_id
    WHERE i.company_id = p_company_id AND rs.margin < (ps.margin * 0.8);
END;
$$ LANGUAGE plpgsql;

-- Update get_alerts function to include profit warnings
CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid)
 RETURNS TABLE(type text, sku text, product_name text, product_id uuid, current_stock integer, reorder_point integer, last_sold_date date, value numeric, days_of_stock_remaining numeric, recent_margin numeric, previous_margin numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    settings_row record;
BEGIN
    SELECT cs.* INTO settings_row FROM company_settings cs WHERE cs.company_id = p_company_id;

    RETURN QUERY
    -- Low Stock Alerts
    SELECT
        'low_stock'::text,
        i.sku,
        i.name,
        i.id,
        i.quantity,
        i.reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::numeric,
        CASE WHEN daily_sales_velocity > 0 THEN i.quantity / daily_sales_velocity ELSE NULL END,
        NULL::numeric,
        NULL::numeric
    FROM inventory i
    LEFT JOIN (
        SELECT
            si.product_id,
            SUM(si.quantity)::numeric / settings_row.fast_moving_days as daily_sales_velocity
        FROM sale_items si JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - (settings_row.fast_moving_days || ' day')::interval
        GROUP BY si.product_id
    ) as sales_velocity ON i.id = sales_velocity.product_id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.reorder_point IS NOT NULL AND i.quantity <= i.reorder_point

    UNION ALL

    -- Dead Stock Alerts
    SELECT
        'dead_stock'::text,
        i.sku,
        i.name,
        i.id,
        i.quantity,
        i.reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::numeric,
        NULL::numeric,
        NULL::numeric,
        NULL::numeric
    FROM inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.last_sold_date < (now() - (settings_row.dead_stock_days || ' day')::interval)

    UNION ALL
    
    -- Predictive Out-of-Stock Alerts
    SELECT
        'predictive'::text,
        i.sku,
        i.name,
        i.id,
        i.quantity,
        i.reorder_point,
        i.last_sold_date,
        (i.quantity * i.cost)::numeric,
        CASE WHEN daily_sales_velocity > 0 THEN i.quantity / daily_sales_velocity ELSE NULL END,
        NULL::numeric,
        NULL::numeric
    FROM inventory i
    JOIN (
        SELECT
            si.product_id,
            SUM(si.quantity)::numeric / settings_row.fast_moving_days as daily_sales_velocity
        FROM sale_items si JOIN sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - (settings_row.fast_moving_days || ' day')::interval
        GROUP BY si.product_id
    ) as sales_velocity ON i.id = sales_velocity.product_id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND daily_sales_velocity > 0 AND (i.quantity / daily_sales_velocity) <= settings_row.predictive_stock_days

    UNION ALL
    
    -- Profit Warning Alerts
    SELECT * FROM get_profit_warning_alerts(p_company_id);

END;
$function$;


-- Final check to ensure all row level security is enabled
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow users to see their own company's audit logs" ON public.audit_log FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.company_id = public.audit_log.company_id));

-- Add remaining policies for new tables
CREATE POLICY "Allow admins to see sync logs" ON public.sync_logs FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.sync_logs.company_id AND role IN ('Admin', 'Owner')));
CREATE POLICY "Allow admins to see sync state" ON public.sync_state FOR SELECT USING (auth.uid() IN (SELECT id FROM users WHERE company_id = public.sync_state.company_id AND role IN ('Admin', 'Owner')));
CREATE POLICY "Allow users to manage their own export jobs" ON public.export_jobs FOR ALL USING (requested_by_user_id = auth.uid());
