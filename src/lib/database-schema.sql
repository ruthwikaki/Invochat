-- InvoChat - Conversational Inventory Intelligence
-- © 2024 Google LLC. All rights reserved.
--
-- Main SQL schema for the InvoChat application.
-- To set up your database, run this entire script in your Supabase SQL Editor.
-- Make sure to enable the 'uuid-ossp' extension in your Supabase project first.

-- -----------------------------------------------------------------------------
-- SECTION 1: EXTENSIONS, TYPES, AND INITIAL SETUP
-- -----------------------------------------------------------------------------

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Define custom user roles for application-level security
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- -----------------------------------------------------------------------------
-- SECTION 2: CORE TABLES
-- -----------------------------------------------------------------------------

-- Stores company information
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);

-- Extends auth.users with app-specific metadata like company and role
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    email text,
    role public.user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON public.users(company_id);

-- Stores company-specific settings and business rules
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id),
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000.00,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text
);

-- Stores supplier information
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_suppliers_name_company ON public.suppliers(name, company_id);

-- Stores core product information
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    cost numeric NOT NULL DEFAULT 0, -- Stored in cents
    price numeric, -- Stored in cents
    reorder_point integer,
    last_sold_date date,
    barcode text,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES auth.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id),
    UNIQUE (company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_sku_company ON public.inventory(sku, company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_category ON public.inventory(company_id, category);
CREATE INDEX IF NOT EXISTS idx_inventory_deleted_at ON public.inventory(deleted_at);


-- Stores customer information
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0, -- Stored in cents
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);
CREATE INDEX IF NOT EXISTS idx_sales_customer_email ON public.customers(email, company_id);


-- Stores individual sales transactions
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    sale_number text NOT NULL UNIQUE,
    customer_name text,
    customer_email text,
    total_amount numeric NOT NULL, -- Stored in cents
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    external_id text
);
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON public.sales(created_at, company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);


-- Stores line items for each sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id),
    sku text NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL, -- Stored in cents
    cost_at_time numeric, -- Stored in cents
    company_id uuid NOT NULL REFERENCES public.companies(id),
    UNIQUE(sale_id, sku)
);

-- Stores historical inventory changes (audit trail)
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    product_id uuid NOT NULL REFERENCES public.inventory(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    related_id uuid, -- e.g., sale_id or purchase_order_id
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);


-- Stores AI chat conversations
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Stores individual messages within a conversation
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamptz DEFAULT now(),
    is_error boolean DEFAULT false
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at ON public.messages(conversation_id, created_at);

-- Stores e-commerce platform integrations
CREATE TABLE IF NOT EXISTS public.integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamptz,
    sync_status text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (company_id, platform)
);

-- Stores logs for individual sync jobs
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES public.integrations(id),
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Stores cursor/state for resumable syncs
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL REFERENCES public.integrations(id),
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamptz,
    PRIMARY KEY (integration_id, sync_type)
);


-- Stores data export job requests
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending', -- pending, processing, complete, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Stores general audit information
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES public.companies(id),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

-- Stores sales channel fees for profit calculations
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id),
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL, -- e.g., 0.029 for 2.9%
    fixed_fee numeric NOT NULL, -- in cents, e.g., 30 for $0.30
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

-- -----------------------------------------------------------------------------
-- SECTION 3: TRIGGERS AND AUTOMATION
-- -----------------------------------------------------------------------------

-- Trigger function to automatically create a company and user profile on new user signup
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

    -- Create a corresponding user profile in public.users
    INSERT INTO public.users (id, company_id, email, role)
    VALUES (new.id, new_company_id, new.email, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id and role
    -- This is crucial for Row Level Security (RLS) policies
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
        '{role}',
        to_jsonb('Owner'::text)
    )
    WHERE id = new.id;

    RETURN new;
END;
$$;

-- Attaching the trigger to the auth.users table
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Trigger function to handle optimistic concurrency control via versioning
CREATE OR REPLACE FUNCTION public.increment_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.version = OLD.version + 1;
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Attaching the versioning trigger to the inventory table
CREATE TRIGGER handle_inventory_update
    BEFORE UPDATE ON public.inventory
    FOR EACH ROW EXECUTE PROCEDURE public.increment_version();


-- -----------------------------------------------------------------------------
-- SECTION 4: ROW LEVEL SECURITY (RLS)
-- -----------------------------------------------------------------------------
-- This is the core of the multi-tenant security model. It ensures that users
-- can only access data belonging to their own company.

-- Enable RLS on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Utility function to get the current user's company_id from their auth token
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;

-- Utility function to get the current user's role from their auth token
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::text;
$$;

-- RLS Policies
-- Users can only see their own company's record
CREATE POLICY "Users can view own company" ON public.companies FOR SELECT USING (id = public.get_my_company_id());

-- Users can see all users within their own company
CREATE POLICY "Users can view other users in their company" ON public.users FOR SELECT USING (company_id = public.get_my_company_id());

-- Owners can update roles of users in their company (but not their own)
CREATE POLICY "Owners can update user roles" ON public.users FOR UPDATE USING (
    company_id = public.get_my_company_id() AND
    public.get_my_role() = 'Owner' AND
    id <> auth.uid()
) WITH CHECK (
    company_id = public.get_my_company_id() AND
    public.get_my_role() = 'Owner'
);


-- Generic policy for most tables: users can access data for their own company
CREATE POLICY "User can access their own company data" ON public.company_settings FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.inventory FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.sales FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.sale_items FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.suppliers FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.customers FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.conversations FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.messages FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.integrations FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.sync_logs FOR ALL USING (company_id = (SELECT company_id FROM public.integrations WHERE id = sync_logs.integration_id));
CREATE POLICY "User can access their own company data" ON public.sync_state FOR ALL USING (company_id = (SELECT company_id FROM public.integrations WHERE id = sync_state.integration_id));
CREATE POLICY "User can access their own company data" ON public.export_jobs FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.audit_log FOR ALL USING (company_id = public.get_my_company_id());
CREATE POLICY "User can access their own company data" ON public.channel_fees FOR ALL USING (company_id = public.get_my_company_id());


-- -----------------------------------------------------------------------------
-- SECTION 5: VIEWS
-- -----------------------------------------------------------------------------
-- These views simplify complex queries and can be materialized for performance.

-- A unified view for inventory details, joining with suppliers
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
WHERE i.deleted_at IS NULL;

-- A materialized view for dashboard metrics to improve performance
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
    i.company_id,
    SUM(i.quantity * i.cost) / 100.0 AS inventory_value,
    COUNT(*) FILTER (WHERE i.quantity < i.reorder_point) AS low_stock_count,
    COUNT(*) AS total_skus
FROM
    public.inventory i
WHERE i.deleted_at IS NULL
GROUP BY
    i.company_id;

CREATE UNIQUE INDEX IF NOT EXISTS company_dashboard_metrics_pkey ON public.company_dashboard_metrics(company_id);

-- A materialized view for customer analytics
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customer_analytics_metrics AS
SELECT
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    COUNT(s.id) as total_orders,
    SUM(s.total_amount) as total_spent
FROM
    public.customers c
JOIN
    public.sales s ON c.id = (
        SELECT id FROM public.customers WHERE email = s.customer_email AND company_id = s.company_id LIMIT 1
    )
WHERE c.deleted_at IS NULL
GROUP BY
    c.id, c.company_id, c.customer_name, c.email;

CREATE UNIQUE INDEX IF NOT EXISTS customer_analytics_metrics_pkey ON public.customer_analytics_metrics(id);

-- -----------------------------------------------------------------------------
-- SECTION 6: STORED PROCEDURES (FUNCTIONS)
-- -----------------------------------------------------------------------------
-- These functions encapsulate business logic at the database level for efficiency,
-- security, and reusability.

-- Function to refresh all materialized views for a company
CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.customer_analytics_metrics;
END;
$$;


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
    new_sale public.sales;
    new_customer_id uuid;
    item record;
    total_sale_amount numeric := 0;
    inventory_item public.inventory;
BEGIN
    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email, now())
        ON CONFLICT (company_id, email) DO UPDATE SET
            customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- Calculate total sale amount
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(
        sku text,
        product_name text,
        quantity integer,
        unit_price numeric,
        cost_at_time numeric
    )
    LOOP
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    VALUES (
        p_company_id,
        'INV-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substr(md5(random()::text), 1, 6),
        p_customer_name,
        p_customer_email,
        total_sale_amount,
        p_payment_method,
        p_notes,
        p_external_id
    )
    RETURNING * INTO new_sale;

    -- Insert sale items and update inventory
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(
        sku text,
        product_name text,
        quantity integer,
        unit_price numeric,
        cost_at_time numeric
    )
    LOOP
        -- Find the inventory item
        SELECT * INTO inventory_item FROM public.inventory WHERE sku = item.sku AND company_id = p_company_id AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product with SKU % not found.', item.sku;
        END IF;

        INSERT INTO public.sale_items (sale_id, company_id, sku, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item.sku, item.product_name, item.quantity, item.unit_price, COALESCE(item.cost_at_time, inventory_item.cost));

        -- Update inventory quantity and log the change
        UPDATE public.inventory
        SET
            quantity = quantity - item.quantity,
            last_sold_date = now()
        WHERE id = inventory_item.id;

        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, inventory_item.id, 'sale', -item.quantity, inventory_item.quantity - item.quantity, new_sale.id);
    END LOOP;

    RETURN new_sale;
END;
$$;


-- Function to get main dashboard metrics
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days int DEFAULT 30)
RETURNS json
LANGUAGE sql
STABLE
AS $$
WITH date_range AS (
    SELECT
        date_trunc('day', now() - (n || ' days')::interval) AS date
    FROM
        generate_series(0, p_days - 1) n
),
daily_sales AS (
    SELECT
        date_trunc('day', s.created_at) as sale_date,
        SUM(s.total_amount) / 100.0 as total_revenue,
        SUM(si.quantity * si.cost_at_time) / 100.0 as total_cogs
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id
      AND s.created_at >= now() - (p_days || ' days')::interval
    GROUP BY 1
)
SELECT json_build_object(
    'totalSalesValue', (SELECT SUM(total_amount) FROM public.sales WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
    'totalProfit', (SELECT SUM(s.total_amount - (SELECT SUM(si.quantity * si.cost_at_time) FROM public.sale_items si WHERE si.sale_id = s.id)) FROM public.sales s WHERE s.company_id = p_company_id AND s.created_at >= now() - (p_days || ' days')::interval),
    'totalOrders', (SELECT COUNT(*) FROM public.sales WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
    'averageOrderValue', (SELECT AVG(total_amount) FROM public.sales WHERE company_id = p_company_id AND created_at >= now() - (p_days || ' days')::interval),
    'deadStockItemsCount', (SELECT COUNT(*) FROM public.inventory WHERE company_id = p_company_id AND deleted_at IS NULL AND (last_sold_date IS NULL OR last_sold_date < now() - '90 days'::interval)),
    'salesTrendData', (
        SELECT json_agg(json_build_object('date', to_char(dr.date, 'YYYY-MM-DD'), 'Sales', COALESCE(ds.total_revenue, 0)))
        FROM date_range dr
        LEFT JOIN daily_sales ds ON dr.date = ds.sale_date
    ),
    'inventoryByCategoryData', (SELECT json_agg(t) FROM (SELECT category, SUM(quantity * cost) / 100.0 as value FROM public.inventory WHERE company_id = p_company_id AND deleted_at IS NULL AND category IS NOT NULL GROUP BY category ORDER BY value DESC LIMIT 5) t),
    'topCustomersData', (SELECT json_agg(t) FROM (SELECT customer_name as name, SUM(total_amount) / 100.0 as value FROM public.sales WHERE company_id = p_company_id AND customer_name IS NOT NULL AND created_at >= now() - (p_days || ' days')::interval GROUP BY customer_name ORDER BY value DESC LIMIT 5) t)
)
FROM (SELECT 1) AS dummy;
$$;


-- Function to get a company's distinct inventory categories
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT category
    FROM public.inventory
    WHERE company_id = p_company_id AND category IS NOT NULL AND deleted_at IS NULL;
$$;


-- Function to get reorder suggestions based on stock levels
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE (
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_id uuid,
    supplier_name text,
    unit_cost numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        COALESCE(i.reorder_quantity, i.reorder_point * 2, 10) as suggested_reorder_quantity,
        s.id as supplier_id,
        s.name as supplier_name,
        i.cost as unit_cost
    FROM
        public.inventory i
    LEFT JOIN
        public.suppliers s ON i.supplier_id = s.id
    WHERE
        i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND i.quantity <= i.reorder_point;
$$;

-- Function for health check: inventory consistency
CREATE OR REPLACE FUNCTION public.health_check_inventory_consistency(p_company_id uuid)
RETURNS TABLE(healthy boolean, metric numeric, message text)
LANGUAGE plpgsql
AS $$
DECLARE
    inconsistent_count int;
BEGIN
    SELECT COUNT(*)
    INTO inconsistent_count
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity <> (
          SELECT COALESCE(SUM(il.quantity_change), 0)
          FROM public.inventory_ledger il
          WHERE il.product_id = i.id AND il.company_id = p_company_id
      );

    IF inconsistent_count = 0 THEN
        RETURN QUERY SELECT true, 0, 'All inventory levels match their transaction ledgers.';
    ELSE
        RETURN QUERY SELECT false, inconsistent_count, inconsistent_count || ' products have quantities that do not match their ledger history. Consider a stock reconciliation.';
    END IF;
END;
$$;

-- Function for health check: financial consistency
CREATE OR REPLACE FUNCTION public.health_check_financial_consistency(p_company_id uuid)
RETURNS TABLE(healthy boolean, metric numeric, message text)
LANGUAGE plpgsql
AS $$
DECLARE
    inconsistent_sum diff;
BEGIN
    SELECT SUM(s.total_amount - si.line_total)
    INTO inconsistent_sum
    FROM public.sales s
    JOIN (
        SELECT sale_id, SUM(quantity * unit_price) as line_total
        FROM public.sale_items
        WHERE company_id = p_company_id
        GROUP BY sale_id
    ) si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id;

    IF COALESCE(inconsistent_sum, 0) = 0 THEN
        RETURN QUERY SELECT true, 0, 'All sale totals match the sum of their line items.';
    ELSE
        RETURN QUERY SELECT false, inconsistent_sum, 'Discrepancy of $' || (inconsistent_sum / 100.0)::text || ' found between sale totals and line item sums.';
    END IF;
END;
$$;

-- Function to get a combined view of schema and sample data for the data explorer page
CREATE OR REPLACE FUNCTION public.get_schema_and_data(p_company_id uuid)
RETURNS json
LANGUAGE sql
AS $$
SELECT json_agg(
    json_build_object(
        'tableName', table_name,
        'rows', (
            SELECT json_agg(t)
            FROM (
                SELECT *
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_name = tbl.table_name
                LIMIT 5
            ) t
        )
    )
)
FROM (
    VALUES
        ('inventory'),
        ('sales'),
        ('customers'),
        ('suppliers')
) AS tbl(table_name);
$$;

-- Function to get inventory aging report data
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    days_since_last_sale integer
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        (i.quantity * i.cost) AS total_value,
        COALESCE(EXTRACT(DAY FROM now() - i.last_sold_date), 9999) AS days_since_last_sale
    FROM
        public.inventory i
    WHERE
        i.company_id = p_company_id
        AND i.deleted_at IS NULL
    ORDER BY
        days_since_last_sale DESC;
$$;

-- Function to get product lifecycle analysis data
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    summary json;
    products_data json;
BEGIN
    WITH product_sales_stats AS (
        SELECT
            i.id as product_id,
            i.sku,
            i.name as product_name,
            i.created_at,
            MIN(s.created_at) as first_sale,
            MAX(s.created_at) as last_sale,
            COUNT(s.id) as total_sales,
            SUM(si.quantity) as total_quantity,
            SUM(si.quantity * si.unit_price) as total_revenue,
            (now() - i.created_at) as age,
            (
                SELECT SUM(si2.quantity)
                FROM public.sale_items si2
                JOIN public.sales s2 ON si2.sale_id = s2.id
                WHERE si2.sku = i.sku AND s2.company_id = p_company_id AND s2.created_at > now() - '90 days'::interval
            ) as sales_last_90d,
            (
                SELECT SUM(si3.quantity)
                FROM public.sale_items si3
                JOIN public.sales s3 ON si3.sale_id = s3.id
                WHERE si3.sku = i.sku AND s3.company_id = p_company_id AND s3.created_at BETWEEN now() - '180 days'::interval AND now() - '91 days'::interval
            ) as sales_prev_90d
        FROM public.inventory i
        LEFT JOIN public.sale_items si ON i.sku = si.sku AND i.company_id = si.company_id
        LEFT JOIN public.sales s ON si.sale_id = s.id
        WHERE i.company_id = p_company_id
        GROUP BY i.id
    ),
    product_stages AS (
        SELECT
            *,
            CASE
                WHEN first_sale > now() - '60 days'::interval THEN 'Launch'
                WHEN sales_last_90d > sales_prev_90d * 1.2 THEN 'Growth'
                WHEN sales_last_90d <= sales_prev_90d * 0.8 AND age > '180 days'::interval THEN 'Decline'
                ELSE 'Maturity'
            END as stage
        FROM product_sales_stats
    )
    SELECT
        json_build_object(
            'launch_count', COUNT(*) FILTER (WHERE stage = 'Launch'),
            'growth_count', COUNT(*) FILTER (WHERE stage = 'Growth'),
            'maturity_count', COUNT(*) FILTER (WHERE stage = 'Maturity'),
            'decline_count', COUNT(*) FILTER (WHERE stage = 'Decline')
        ) INTO summary
    FROM product_stages;

    SELECT
        json_agg(
            json_build_object(
                'sku', sku,
                'product_name', product_name,
                'stage', stage,
                'total_revenue', total_revenue,
                'total_sales', total_sales,
                'age_days', EXTRACT(DAY FROM age)
            )
        ) INTO products_data
    FROM (
        SELECT *
        FROM product_stages
        ORDER BY
            CASE stage
                WHEN 'Launch' THEN 1
                WHEN 'Growth' THEN 2
                WHEN 'Maturity' THEN 3
                WHEN 'Decline' THEN 4
            END,
            total_revenue DESC
    ) as sorted_products;

    RETURN json_build_object(
        'summary', summary,
        'products', products_data
    );
END;
$$;


-- Function to get inventory risk report data
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    risk_score integer,
    risk_level text,
    total_value numeric,
    reason text
)
LANGUAGE sql
STABLE
AS $$
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name as product_name,
            (i.quantity * i.cost) as total_value,
            COALESCE(EXTRACT(DAY FROM now() - i.last_sold_date), 365) as days_since_last_sale,
            -- Sell-through rate (simple version)
            (
                SELECT SUM(si.quantity)
                FROM public.sale_items si
                JOIN public.sales s ON si.sale_id = s.id
                WHERE si.sku = i.sku AND s.company_id = i.company_id AND s.created_at > now() - '90 days'::interval
            ) / NULLIF(i.quantity + (
                SELECT SUM(si.quantity)
                FROM public.sale_items si
                JOIN public.sales s ON si.sale_id = s.id
                WHERE si.sku = i.sku AND s.company_id = i.company_id AND s.created_at > now() - '90 days'::interval
            ), 0) as sell_through_rate
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    )
    SELECT
        sku,
        product_name,
        (
            -- Score calculation (0-100)
            LEAST(100,
                -- Days since last sale (up to 40 points)
                (days_since_last_sale / 180.0) * 40 +
                -- Value at risk (up to 30 points)
                (total_value / (SELECT MAX(total_value) FROM risk_factors)) * 30 +
                -- Sell-through rate (up to 30 points, inverse)
                (1 - COALESCE(sell_through_rate, 0)) * 30
            )
        )::integer as risk_score,
        CASE
            WHEN LEAST(100, (days_since_last_sale / 180.0) * 40 + (total_value / (SELECT MAX(total_value) FROM risk_factors)) * 30 + (1 - COALESCE(sell_through_rate, 0)) * 30) > 75 THEN 'High'
            WHEN LEAST(100, (days_since_last_sale / 180.0) * 40 + (total_value / (SELECT MAX(total_value) FROM risk_factors)) * 30 + (1 - COALESCE(sell_through_rate, 0)) * 30) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        total_value,
        'Days since last sale: ' || days_since_last_sale || ', Sell-through: ' || COALESCE(ROUND(sell_through_rate * 100, 2), 0) || '%' as reason
    FROM risk_factors
    ORDER BY risk_score DESC;
$$;


-- Function to get customer segment analysis data
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity bigint,
    total_revenue numeric
)
LANGUAGE sql
STABLE
AS $$
WITH customer_segments AS (
    SELECT
        c.id,
        c.email,
        CASE
            WHEN c.first_order_date > now() - '30 days'::interval THEN 'New Customers'
            WHEN c.total_orders > 1 THEN 'Repeat Customers'
            ELSE 'Other'
        END as segment,
        CASE
            WHEN c.total_spent > (SELECT percentile_cont(0.8) WITHIN GROUP (ORDER BY total_spent) FROM public.customers WHERE company_id = p_company_id) THEN 'Top Spenders'
            ELSE NULL
        END as secondary_segment
    FROM public.customers c
    WHERE c.company_id = p_company_id AND c.deleted_at IS NULL
),
segmented_sales AS (
    SELECT
        s.id as sale_id,
        COALESCE(cs.segment, cs2.segment, 'Other') as final_segment
    FROM public.sales s
    LEFT JOIN customer_segments cs ON s.customer_email = cs.email
    LEFT JOIN customer_segments cs2 ON s.customer_email = cs2.email AND cs2.secondary_segment IS NOT NULL
    WHERE s.company_id = p_company_id
)
SELECT
    ss.final_segment as segment,
    si.sku,
    si.product_name,
    SUM(si.quantity)::bigint as total_quantity,
    SUM(si.quantity * si.unit_price) as total_revenue
FROM public.sale_items si
JOIN segmented_sales ss ON si.sale_id = ss.sale_id
WHERE si.company_id = p_company_id AND ss.final_segment <> 'Other'
GROUP BY
    ss.final_segment,
    si.sku,
    si.product_name
ORDER BY
    segment,
    total_revenue DESC;
$$;

-- Function to get cash flow insights
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS json
LANGUAGE sql
STABLE
AS $$
SELECT json_build_object(
    'dead_stock_value', (SELECT COALESCE(SUM(quantity * cost), 0) FROM public.inventory WHERE company_id = p_company_id AND last_sold_date < now() - '90 days'::interval),
    'slow_mover_value', (SELECT COALESCE(SUM(quantity * cost), 0) FROM public.inventory WHERE company_id = p_company_id AND last_sold_date BETWEEN now() - '90 days'::interval AND now() - '30 days'::interval),
    'dead_stock_threshold_days', (SELECT dead_stock_days FROM public.company_settings WHERE company_id = p_company_id)
);
$$;

-- Function to get supplier performance report data
CREATE OR REPLACE FUNCTION public.get_supplier_performance_report(p_company_id uuid)
RETURNS TABLE (
    supplier_name text,
    total_profit numeric,
    avg_margin numeric,
    sell_through_rate numeric
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.name as supplier_name,
        SUM(si.unit_price - si.cost_at_time) as total_profit,
        AVG((si.unit_price - si.cost_at_time) / NULLIF(si.unit_price, 0)) as avg_margin,
        SUM(si.quantity) / NULLIF(SUM(i.quantity + si.quantity), 0) as sell_through_rate
    FROM public.suppliers s
    JOIN public.inventory i ON s.id = i.supplier_id
    JOIN public.sale_items si ON i.sku = si.sku AND i.company_id = si.company_id
    WHERE s.company_id = p_company_id
    GROUP BY s.name;
$$;

-- Function to get inventory turnover report data
CREATE OR REPLACE FUNCTION public.get_inventory_turnover_report(p_company_id uuid, p_days integer)
RETURNS TABLE (
    turnover_rate numeric,
    total_cogs numeric,
    average_inventory_value numeric,
    period_days integer
)
LANGUAGE sql
STABLE
AS $$
    WITH period_cogs AS (
        SELECT SUM(si.quantity * si.cost_at_time) as total_cogs
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - (p_days || ' days')::interval
    ),
    avg_inventory AS (
        SELECT AVG(daily_value) as avg_value
        FROM (
            SELECT date_trunc('day', d) as day, (SELECT SUM(cost * quantity) FROM public.inventory WHERE company_id = p_company_id AND created_at <= d) as daily_value
            FROM generate_series(now() - (p_days || ' days')::interval, now(), '1 day') d
        ) daily_inventories
    )
    SELECT
        pc.total_cogs / NULLIF(ai.avg_value, 0) as turnover_rate,
        pc.total_cogs,
        ai.avg_value as average_inventory_value,
        p_days as period_days
    FROM period_cogs pc, avg_inventory ai;
$$;

-- Function to get profit warning alerts data
CREATE OR REPLACE FUNCTION public.get_profit_warning_alerts(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    product_id uuid,
    recent_margin numeric,
    previous_margin numeric
)
LANGUAGE sql
STABLE
AS $$
    WITH recent_sales AS (
        SELECT
            si.sku,
            AVG((si.unit_price - si.cost_at_time) / NULLIF(si.unit_price, 0)) as margin
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at >= now() - '90 days'::interval
        GROUP BY si.sku
    ),
    previous_sales AS (
        SELECT
            si.sku,
            AVG((si.unit_price - si.cost_at_time) / NULLIF(si.unit_price, 0)) as margin
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id AND s.created_at BETWEEN now() - '180 days'::interval AND now() - '91 days'::interval
        GROUP BY si.sku
    )
    SELECT
        rs.sku,
        i.name as product_name,
        i.id as product_id,
        rs.margin as recent_margin,
        ps.margin as previous_margin
    FROM recent_sales rs
    JOIN previous_sales ps ON rs.sku = ps.sku
    JOIN public.inventory i ON rs.sku = i.sku AND i.company_id = p_company_id
    WHERE rs.margin < ps.margin * 0.8; -- 20% drop in margin
$$;

-- Function to analyze financial impact of a potential promotion
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS json
LANGUAGE sql
STABLE
AS $$
    WITH product_metrics AS (
        SELECT
            sku,
            (SELECT SUM(quantity) FROM public.sale_items si JOIN public.sales s ON si.sale_id = s.id WHERE si.sku = i.sku AND s.company_id = p_company_id AND s.created_at > now() - '90 days'::interval) / 90.0 as avg_daily_sales,
            (price - cost) as profit_per_unit
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.sku = ANY(p_skus)
    ),
    -- Simple elasticity model: assume 20% discount -> 40% sales lift
    elasticity_factor AS (SELECT 1.0 + (p_discount_percentage * 2.0) as sales_lift),
    projected_sales AS (
        SELECT
            pm.sku,
            (pm.avg_daily_sales * ef.sales_lift * p_duration_days) as projected_units,
            (i.price * (1 - p_discount_percentage)) as discounted_price,
            (i.price * (1 - p_discount_percentage) - i.cost) as discounted_profit_per_unit
        FROM product_metrics pm
        JOIN public.inventory i ON pm.sku = i.sku AND i.company_id = p_company_id
        CROSS JOIN elasticity_factor ef
    )
    SELECT json_build_object(
        'total_projected_revenue', (SELECT SUM(projected_units * discounted_price) FROM projected_sales),
        'total_projected_profit', (SELECT SUM(projected_units * discounted_profit_per_unit) FROM projected_sales),
        'estimated_units_sold', (SELECT SUM(projected_units) FROM projected_sales),
        'items', (SELECT json_agg(ps) FROM projected_sales ps)
    );
$$;

-- Update get_alerts to include new profit warnings
DROP FUNCTION IF EXISTS public.get_alerts(uuid, integer, integer, integer);
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
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    -- Low Stock Alerts
    SELECT
        'low_stock_' || i.sku as id,
        'low_stock' as type,
        'Low Stock Warning' as title,
        i.name || ' is running low on stock.' as message,
        'warning' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'reorderPoint', i.reorder_point
        ) as metadata
    FROM public.inventory i
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity > 0
      AND i.reorder_point IS NOT NULL
      AND i.quantity <= i.reorder_point

    UNION ALL

    -- Dead Stock Alerts
    SELECT
        'dead_stock_' || i.sku as id,
        'dead_stock' as type,
        'Dead Stock Alert' as title,
        i.name || ' has not sold recently.' as message,
        'info' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', i.id,
            'productName', i.name,
            'currentStock', i.quantity,
            'lastSoldDate', i.last_sold_date,
            'value', (i.quantity * i.cost)
        ) as metadata
    FROM public.inventory i
    JOIN public.company_settings cs ON cs.company_id = i.company_id
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.quantity > 0
      AND i.last_sold_date < (now() - (cs.dead_stock_days || ' days')::interval)

    UNION ALL

    -- Predictive Stockout Alerts
    SELECT
        'predictive_' || p.sku as id,
        'predictive' as type,
        'Predictive Stockout Alert' as title,
        'Predicted to run out of ' || p.product_name || ' soon.' as message,
        'warning' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', p.product_id,
            'productName', p.product_name,
            'currentStock', p.quantity,
            'daysOfStockRemaining', p.days_of_stock_remaining
        ) as metadata
    FROM (
        SELECT
            i.id as product_id,
            i.sku,
            i.name as product_name,
            i.quantity,
            i.quantity / NULLIF((
                SELECT SUM(si.quantity)
                FROM public.sale_items si JOIN sales s ON si.sale_id = s.id
                WHERE s.company_id = i.company_id
                  AND si.sku = i.sku
                  AND s.created_at >= (now() - (cs.fast_moving_days || ' days')::interval)
            ) / cs.fast_moving_days::decimal, 0) as days_of_stock_remaining
        FROM public.inventory i
        JOIN public.company_settings cs ON cs.company_id = i.company_id
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    ) p
    WHERE p.days_of_stock_remaining <= (SELECT predictive_stock_days FROM public.company_settings WHERE company_id = p_company_id)

    UNION ALL

    -- Profit Warning Alerts
    SELECT
        'profit_warning_' || pwa.sku as id,
        'profit_warning' as type,
        'Profit Margin Warning' as title,
        'Profit margin for ' || pwa.product_name || ' has decreased significantly.' as message,
        'critical' as severity,
        now() as "timestamp",
        jsonb_build_object(
            'productId', pwa.product_id,
            'productName', pwa.product_name,
            'recent_margin', pwa.recent_margin,
            'previous_margin', pwa.previous_margin
        ) as metadata
    FROM public.get_profit_warning_alerts(p_company_id) pwa;

END;
$$;
