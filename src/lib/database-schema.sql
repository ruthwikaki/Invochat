--
-- This script contains the full database schema for the InvoChat application.
-- It is designed to be idempotent and can be run safely multiple times.
--
-- For a new project: Run this entire script in your Supabase SQL Editor.
-- For an existing project: You can run this script again to apply updates.
--

-- =============================================================================
-- Extensions
-- =============================================================================
-- These extensions provide additional functionality to the database.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "moddatetime"; -- To automatically update `updated_at` timestamps

-- =============================================================================
-- Types
-- =============================================================================
-- Custom data types to enforce consistency across the schema.

-- Drop the type if it exists to ensure the definition is up-to-date
DROP TYPE IF EXISTS public.user_role CASCADE;
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- =============================================================================
-- Tables
-- =============================================================================

-- Table to store company information
CREATE TABLE IF NOT EXISTS public.companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

-- Add company_id and role to Supabase's auth.users table's metadata
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    company_id UUID REFERENCES public.companies(id),
    role user_role NOT NULL DEFAULT 'Member'
);
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Table for suppliers/vendors
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    CONSTRAINT suppliers_company_id_name_key UNIQUE (company_id, name)
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Core inventory table
CREATE TABLE IF NOT EXISTS public.inventory (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    category TEXT,
    price INT, -- in cents
    cost INT NOT NULL DEFAULT 0, -- in cents
    quantity INT NOT NULL DEFAULT 0,
    reorder_point INT,
    reorder_quantity INT,
    supplier_id UUID REFERENCES public.suppliers(id),
    barcode TEXT,
    source_platform TEXT,
    external_product_id TEXT,
    external_variant_id TEXT,
    external_quantity INT,
    last_sync_at TIMESTAMPTZ,
    last_sold_date TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ,
    version INT NOT NULL DEFAULT 1
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX IF NOT EXISTS inventory_company_sku_unique_idx ON public.inventory (company_id, sku) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_supplier_id ON public.inventory(supplier_id);

-- Table for inventory history and audit trail
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.inventory(id),
    change_type TEXT NOT NULL,
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_id ON public.inventory_ledger(company_id);

-- Table for customers
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS customers_company_id_email_key ON public.customers (company_id, email) WHERE deleted_at IS NULL;

-- Table for sales transactions
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number TEXT NOT NULL UNIQUE,
    customer_id UUID REFERENCES public.customers(id),
    total_amount INT NOT NULL, -- in cents
    payment_method TEXT,
    notes TEXT,
    created_by UUID REFERENCES auth.users(id),
    external_id TEXT, -- For IDs from external systems like Shopify, WooCommerce
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);

-- Table for individual items in a sale
CREATE TABLE IF NOT EXISTS public.sale_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.inventory(id),
    product_name TEXT NOT NULL,
    quantity INT NOT NULL,
    unit_price INT NOT NULL, -- in cents
    cost_at_time INT NOT NULL, -- in cents
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items(product_id);

-- Company settings table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days INT NOT NULL DEFAULT 90,
  fast_moving_days INT NOT NULL DEFAULT 30,
  predictive_stock_days INT NOT NULL DEFAULT 7,
  overstock_multiplier NUMERIC NOT NULL DEFAULT 3,
  high_value_threshold INT NOT NULL DEFAULT 100000,
  promo_sales_lift_multiplier NUMERIC NOT NULL DEFAULT 2.5,
  currency TEXT DEFAULT 'USD',
  timezone TEXT DEFAULT 'UTC',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sync_status TEXT,
  last_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, platform)
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- Audit log for important actions
CREATE TABLE IF NOT EXISTS public.audit_log (
  id BIGSERIAL PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_audit_log_company_id_action ON public.audit_log(company_id, action);

-- Channel fees for net margin calculations
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  channel_name TEXT NOT NULL,
  percentage_fee NUMERIC NOT NULL,
  fixed_fee INT NOT NULL, -- in cents
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, channel_name)
);
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;

-- Job queue for background tasks
CREATE TABLE IF NOT EXISTS public.export_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
  download_url TEXT,
  expires_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_export_jobs_status ON public.export_jobs(status);


CREATE TABLE IF NOT EXISTS public.sync_state (
  integration_id UUID PRIMARY KEY REFERENCES public.integrations(id) ON DELETE CASCADE,
  sync_type TEXT NOT NULL,
  last_processed_cursor TEXT,
  last_update TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.sync_state ENABLE ROW LEVEL SECURITY;


CREATE TABLE IF NOT EXISTS public.sync_logs (
    id BIGSERIAL PRIMARY KEY,
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL, -- 'products', 'sales'
    status TEXT NOT NULL, -- 'started', 'completed', 'failed'
    records_synced INT,
    error_message TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ
);
ALTER TABLE public.sync_logs ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_sync_logs_integration_id ON public.sync_logs(integration_id);


CREATE TABLE IF NOT EXISTS public.webhook_events (
    id BIGSERIAL PRIMARY KEY,
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    platform TEXT NOT NULL,
    webhook_id TEXT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(integration_id, webhook_id)
);
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- Row Level Security (RLS) Policies
-- =============================================================================

-- Helper function to get the company_id from a user's claims
CREATE OR REPLACE FUNCTION public.get_my_company_id()
RETURNS UUID AS $$
DECLARE
    company_id UUID;
BEGIN
    SELECT a.company_id into company_id from public.users a where a.id = auth.uid();
    RETURN company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Policies for all tables
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name NOT LIKE 'pg_stat_%' AND table_name != 'users')
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
        EXECUTE format('DROP POLICY IF EXISTS "Users can manage their own company''s data" ON public.%I;', t_name);
        EXECUTE format(
            'CREATE POLICY "Users can manage their own company''s data" ON public.%I '
            'FOR ALL USING (company_id = public.get_my_company_id());',
            t_name
        );
    END LOOP;
END;
$$;


-- Specific policy for the users table
DROP POLICY IF EXISTS "Users can view other users in their own company" on public.users;
CREATE POLICY "Users can view other users in their own company"
ON public.users FOR SELECT
USING (company_id = public.get_my_company_id());

DROP POLICY IF EXISTS "Users can update their own profile" on public.users;
CREATE POLICY "Users can update their own profile"
ON public.users FOR UPDATE
USING (id = auth.uid());


-- =============================================================================
-- Triggers and Functions
-- =============================================================================

-- Function to automatically update 'updated_at' timestamps
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply the updated_at trigger to all tables that have the column
DO $$
DECLARE
    t_name TEXT;
BEGIN
    FOR t_name IN (SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'updated_at')
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS on_public_%I_updated_at ON public.%I;', t_name, t_name);
        EXECUTE format(
            'CREATE TRIGGER on_public_%I_updated_at '
            'BEFORE UPDATE ON public.%I '
            'FOR EACH ROW EXECUTE PROCEDURE public.handle_updated_at();',
            t_name, t_name
        );
    END LOOP;
END;
$$;


-- Function to create a company for a new user and link them.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    company_id_var UUID;
    user_role_var user_role;
BEGIN
    -- Create a new company for the user
    INSERT INTO public.companies (name)
    VALUES (new.raw_user_meta_data->>'company_name')
    RETURNING id INTO company_id_var;

    -- Set the user's role to 'Owner'
    user_role_var := 'Owner';

    -- Insert into our public users table
    INSERT INTO public.users (id, company_id, role)
    VALUES (new.id, company_id_var, user_role_var);
    
    -- Update the user's app_metadata in auth.users
    UPDATE auth.users
    SET app_metadata = jsonb_set(
        COALESCE(app_metadata, '{}'::jsonb),
        '{company_id}',
        to_jsonb(company_id_var)
    ) || jsonb_set(
        COALESCE(app_metadata, '{}'::jsonb),
        '{role}',
        to_jsonb(user_role_var)
    )
    WHERE id = new.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';

-- Trigger to call handle_new_user on new user signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Function to update inventory and create a ledger entry
CREATE OR REPLACE FUNCTION public.update_inventory_item_with_lock(
    p_product_id UUID,
    p_company_id UUID,
    p_quantity_change INT,
    p_change_type TEXT,
    p_related_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS INT AS $$
DECLARE
    new_quantity_val INT;
BEGIN
    SET search_path = 'public';

    -- Lock the row for update to prevent race conditions
    UPDATE inventory
    SET quantity = quantity + p_quantity_change
    WHERE id = p_product_id AND company_id = p_company_id
    RETURNING quantity INTO new_quantity_val;

    IF new_quantity_val IS NULL THEN
        RAISE EXCEPTION 'Product with ID % not found for company %', p_product_id, p_company_id;
    END IF;

    -- Insert into ledger
    INSERT INTO inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (p_company_id, p_product_id, p_change_type, p_quantity_change, new_quantity_val, p_related_id, p_notes);

    -- Update last_sold_date if it's a sale
    IF p_change_type = 'sale' THEN
        UPDATE inventory SET last_sold_date = now() WHERE id = p_product_id;
    END IF;
    
    RETURN new_quantity_val;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.update_inventory_item_with_lock(UUID, UUID, INT, TEXT, UUID, TEXT) SET search_path = 'public';

-- Function to handle sale transactions
CREATE OR REPLACE FUNCTION public.record_sale_transaction_v2(
    p_company_id UUID,
    p_user_id UUID,
    p_sale_items JSONB,
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_external_id TEXT
)
RETURNS JSON AS $$
DECLARE
    new_sale_id UUID;
    new_customer_id UUID;
    item RECORD;
    total_sale_amount INT := 0;
    item_cost INT;
    sale_number_val TEXT;
BEGIN
    SET search_path = 'public';

    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO customers (company_id, customer_name, email)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
        ON CONFLICT (company_id, email) WHERE deleted_at IS NULL
        DO UPDATE SET customer_name = COALESCE(p_customer_name, EXCLUDED.customer_name)
        RETURNING id INTO new_customer_id;
    END IF;

    -- Generate a unique sale number
    sale_number_val := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || (
        SELECT COALESCE(MAX(SUBSTRING(sale_number, '\d+$')::int), 0) + 1 FROM sales WHERE sale_number ~ ('INV-' || to_char(now(), 'YYYYMMDD'))
    )::text;

    -- Create sale record
    INSERT INTO sales (company_id, customer_id, total_amount, payment_method, notes, created_by, sale_number, external_id)
    VALUES (p_company_id, new_customer_id, 0, p_payment_method, p_notes, p_user_id, sale_number_val, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Process sale items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id UUID, quantity INT, unit_price INT, product_name TEXT)
    LOOP
        -- Get current cost
        SELECT cost INTO item_cost FROM inventory WHERE id = item.product_id;

        -- Create sale item
        INSERT INTO sale_items (sale_id, company_id, product_id, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, item.product_id, item.product_name, item.quantity, item.unit_price, COALESCE(item_cost, 0));
        
        -- Update inventory
        PERFORM public.update_inventory_item_with_lock(item.product_id, p_company_id, -item.quantity, 'sale', new_sale_id, 'Sale #' || sale_number_val);

        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Update total sale amount
    UPDATE sales SET total_amount = total_sale_amount WHERE id = new_sale_id;

    RETURN json_build_object('sale_id', new_sale_id, 'sale_number', sale_number_val, 'total_amount', total_sale_amount);
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.record_sale_transaction_v2(UUID, UUID, JSONB, TEXT, TEXT, TEXT, TEXT, TEXT) SET search_path = 'public';

-- =============================================================================
-- Materialized Views for Performance
-- =============================================================================

DROP MATERIALIZED VIEW IF EXISTS public.company_dashboard_metrics;
CREATE MATERIALIZED VIEW public.company_dashboard_metrics AS
SELECT
    i.company_id,
    COALESCE(SUM(i.quantity * i.cost), 0) AS inventory_value,
    COUNT(DISTINCT i.id) AS total_skus,
    COALESCE(SUM(CASE WHEN i.quantity <= i.reorder_point THEN 1 ELSE 0 END), 0) AS low_stock_count
FROM
    public.inventory i
WHERE
    i.deleted_at IS NULL
GROUP BY
    i.company_id;
CREATE UNIQUE INDEX ON public.company_dashboard_metrics (company_id);
-- Revoke select permissions from anon and authenticated roles
REVOKE ALL ON public.company_dashboard_metrics FROM anon, authenticated;


DROP MATERIALIZED VIEW IF EXISTS public.customer_analytics_metrics;
CREATE MATERIALIZED VIEW public.customer_analytics_metrics AS
SELECT 
    c.company_id,
    COUNT(c.id) as total_customers,
    COUNT(c.id) FILTER (WHERE c.created_at >= now() - interval '30 days') as new_customers_last_30_days,
    (COUNT(DISTINCT c.id) FILTER (WHERE s.order_count > 1))::numeric / NULLIF(COUNT(DISTINCT c.id), 0) as repeat_customer_rate,
    AVG(s.total_spent) as average_lifetime_value
FROM public.customers c
LEFT JOIN (
    SELECT customer_id, company_id, COUNT(id) as order_count, SUM(total_amount) as total_spent
    FROM public.sales
    GROUP BY customer_id, company_id
) s ON c.id = s.customer_id AND c.company_id = s.company_id
WHERE c.deleted_at IS NULL
GROUP BY c.company_id;
CREATE UNIQUE INDEX ON public.customer_analytics_metrics (company_id);
-- Revoke select permissions from anon and authenticated roles
REVOKE ALL ON public.customer_analytics_metrics FROM anon, authenticated;


-- =============================================================================
-- Database Functions for Application Logic
-- =============================================================================

CREATE OR REPLACE FUNCTION public.refresh_materialized_views(p_company_id UUID)
RETURNS void AS $$
BEGIN
    SET search_path = 'public';
    REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
    REFRESH MATERIALIZED VIEW public.customer_analytics_metrics;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.refresh_materialized_views(UUID) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id UUID, p_days INT)
RETURNS JSON AS $$
BEGIN
    SET search_path = 'public';
    RETURN (
      SELECT json_build_object(
        'totalSalesValue', COALESCE(SUM(s.total_amount), 0),
        'totalProfit', COALESCE(SUM(si.quantity * (si.unit_price - si.cost_at_time)), 0),
        'totalOrders', COUNT(DISTINCT s.id),
        'averageOrderValue', COALESCE(AVG(s.total_amount), 0),
        'deadStockItemsCount', (SELECT COUNT(*) FROM inventory WHERE company_id = p_company_id AND last_sold_date < now() - interval '90 days'),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', d.day, 'Sales', COALESCE(daily_sales.total, 0)))
            FROM generate_series(now() - (p_days - 1) * interval '1 day', now(), interval '1 day') AS d(day)
            LEFT JOIN (
                SELECT date_trunc('day', created_at) AS day, SUM(total_amount) AS total
                FROM sales
                WHERE company_id = p_company_id AND created_at >= now() - (p_days - 1) * interval '1 day'
                GROUP BY 1
            ) AS daily_sales ON d.day = daily_sales.day
        ),
        'inventoryByCategoryData', (
          SELECT json_agg(json_build_object('name', COALESCE(i.category, 'Uncategorized'), 'value', SUM(i.quantity * i.cost)))
          FROM inventory i
          WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
          GROUP BY i.category
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', c.customer_name, 'value', SUM(s.total_amount)))
            FROM sales s JOIN customers c ON s.customer_id = c.id
            WHERE s.company_id = p_company_id AND s.created_at >= now() - (p_days - 1) * interval '1 day'
            GROUP BY c.customer_name ORDER BY SUM(s.total_amount) DESC LIMIT 5
        )
      )
      FROM sales s
      LEFT JOIN sale_items si ON s.id = si.sale_id
      WHERE s.company_id = p_company_id AND s.created_at >= now() - (p_days - 1) * interval '1 day'
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.get_dashboard_metrics(UUID, INT) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id UUID,
    p_query TEXT,
    p_category TEXT,
    p_supplier_id UUID,
    p_sku_filter TEXT[],
    p_limit INT,
    p_offset INT
)
RETURNS JSON AS $$
BEGIN
    SET search_path = 'public';
    RETURN (
        SELECT json_build_object(
            'items', COALESCE(json_agg(i_rows), '[]'),
            'total_count', (
                SELECT COUNT(*) FROM inventory i
                WHERE i.company_id = p_company_id
                AND i.deleted_at IS NULL
                AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
                AND (p_category IS NULL OR i.category = p_category)
                AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
                AND (p_sku_filter IS NULL OR i.sku = ANY(p_sku_filter))
            )
        )
        FROM (
            SELECT
                i.id AS product_id,
                i.sku,
                i.name AS product_name,
                i.category,
                i.quantity,
                i.cost,
                i.price,
                (i.quantity * i.cost) AS total_value,
                i.reorder_point,
                s.name AS supplier_name,
                s.id AS supplier_id,
                i.barcode
            FROM inventory i
            LEFT JOIN suppliers s ON i.supplier_id = s.id
            WHERE i.company_id = p_company_id
            AND i.deleted_at IS NULL
            AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
            AND (p_category IS NULL OR i.category = p_category)
            AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
            AND (p_sku_filter IS NULL OR i.sku = ANY(p_sku_filter))
            ORDER BY i.name
            LIMIT p_limit OFFSET p_offset
        ) AS i_rows
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.get_unified_inventory(UUID, TEXT, TEXT, UUID, TEXT[], INT, INT) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.get_customers_with_stats(p_company_id UUID, p_query TEXT, p_limit INT, p_offset INT)
RETURNS JSON AS $$
BEGIN
    SET search_path = 'public';
    RETURN (
        SELECT json_build_object(
            'items', COALESCE(json_agg(c_rows), '[]'),
            'total_count', (
                SELECT COUNT(*) FROM customers c
                WHERE c.company_id = p_company_id
                AND c.deleted_at IS NULL
                AND (p_query IS NULL OR (c.customer_name ILIKE '%' || p_query || '%' OR c.email ILIKE '%' || p_query || '%'))
            )
        )
        FROM (
            SELECT 
                c.id, c.company_id, c.customer_name, c.email, c.created_at,
                COALESCE(s.total_orders, 0) as total_orders,
                COALESCE(s.total_spent, 0) as total_spent
            FROM customers c
            LEFT JOIN (
                SELECT customer_id, COUNT(id) as total_orders, SUM(total_amount) as total_spent
                FROM sales
                WHERE company_id = p_company_id
                GROUP BY customer_id
            ) s ON c.id = s.customer_id
            WHERE c.company_id = p_company_id
            AND c.deleted_at IS NULL
            AND (p_query IS NULL OR (c.customer_name ILIKE '%' || p_query || '%' OR c.email ILIKE '%' || p_query || '%'))
            ORDER BY c.customer_name
            LIMIT p_limit OFFSET p_offset
        ) as c_rows
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.get_customers_with_stats(UUID, TEXT, INT, INT) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.get_supplier_performance_report(p_company_id UUID)
RETURNS TABLE(supplier_name TEXT, total_profit NUMERIC, avg_margin NUMERIC, sell_through_rate NUMERIC) AS $$
BEGIN
    SET search_path = 'public';
    RETURN QUERY
    SELECT
        s.name AS supplier_name,
        COALESCE(SUM(si.quantity * (si.unit_price - si.cost_at_time)), 0)::NUMERIC AS total_profit,
        COALESCE(AVG(NULLIF(si.unit_price - si.cost_at_time, 0)::float / NULLIF(si.unit_price, 0)), 0)::NUMERIC AS avg_margin,
        (
            COALESCE(SUM(si.quantity), 0)::float /
            NULLIF(COALESCE(SUM(si.quantity), 0) + COALESCE(SUM(i.quantity), 0), 0)
        )::NUMERIC AS sell_through_rate
    FROM suppliers s
    JOIN inventory i ON s.id = i.supplier_id
    LEFT JOIN sale_items si ON i.id = si.product_id
    WHERE s.company_id = p_company_id
    GROUP BY s.name;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.get_supplier_performance_report(UUID) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.health_check_inventory_consistency(p_company_id UUID)
RETURNS JSON AS $$
DECLARE
    ledger_sum INT;
    inventory_sum INT;
    difference INT;
BEGIN
    SET search_path = 'public';
    SELECT SUM(quantity_change) INTO ledger_sum FROM inventory_ledger WHERE company_id = p_company_id;
    SELECT SUM(quantity) INTO inventory_sum FROM inventory WHERE company_id = p_company_id;
    difference := COALESCE(inventory_sum, 0) - COALESCE(ledger_sum, 0);

    RETURN json_build_object(
        'healthy', difference = 0,
        'metric', difference,
        'message', 
            CASE 
                WHEN difference = 0 THEN 'Inventory quantities match ledger records.'
                ELSE 'Mismatch detected between inventory and ledger. Difference: ' || difference
            END
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.health_check_inventory_consistency(UUID) SET search_path = 'public';


CREATE OR REPLACE FUNCTION public.health_check_financial_consistency(p_company_id UUID)
RETURNS JSON AS $$
DECLARE
    sales_total INT;
    sale_items_total BIGINT;
    difference BIGINT;
BEGIN
    SET search_path = 'public';
    SELECT SUM(total_amount) INTO sales_total FROM sales WHERE company_id = p_company_id;
    SELECT SUM(quantity * unit_price) INTO sale_items_total FROM sale_items WHERE company_id = p_company_id;
    difference := COALESCE(sales_total, 0) - COALESCE(sale_items_total, 0);

    RETURN json_build_object(
        'healthy', difference = 0,
        'metric', difference,
        'message', 
            CASE 
                WHEN difference = 0 THEN 'Sales totals are consistent with sale item totals.'
                ELSE 'Mismatch detected between sales and sale items. Difference: $' || (difference / 100.0)
            END
    );
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.health_check_financial_consistency(UUID) SET search_path = 'public';

CREATE OR REPLACE FUNCTION public.reconcile_inventory_from_integration(
    p_integration_id UUID,
    p_company_id UUID
) RETURNS void AS $$
DECLARE
    item RECORD;
BEGIN
    SET search_path = 'public';
    FOR item IN
        SELECT id, sku, quantity, external_quantity
        FROM inventory
        WHERE company_id = p_company_id
        AND last_sync_at IS NOT NULL
        AND external_quantity IS NOT NULL
        AND quantity != external_quantity
        AND id IN (SELECT id FROM inventory WHERE company_id = p_company_id AND last_sync_at IS NOT NULL) -- Ensure we only update items from the integration
    LOOP
        PERFORM public.update_inventory_item_with_lock(
            item.id,
            p_company_id,
            item.external_quantity - item.quantity,
            'reconciliation',
            p_integration_id,
            'Syncing with platform quantity.'
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;
ALTER FUNCTION public.reconcile_inventory_from_integration(UUID, UUID) SET search_path = 'public';


-- Grant usage on the public schema to the Supabase roles
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON FUNCTIONS IN SCHEMA public TO postgres, anon, authenticated, service_role;
