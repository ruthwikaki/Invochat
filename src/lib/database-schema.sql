

-- This is the primary SQL schema for the application.
-- It is designed to be idempotent and can be run multiple times safely.

-- Enable the pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enum types for consistency and data integrity
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'company_role') THEN
        CREATE TYPE public.company_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'integration_platform') THEN
        CREATE TYPE public.integration_platform AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_role') THEN
        CREATE TYPE public.message_role AS ENUM ('user', 'assistant', 'tool');
    END IF;
     IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'feedback_type') THEN
        CREATE TYPE public.feedback_type AS ENUM ('helpful', 'unhelpful');
    END IF;
END
$$;

-- Function to get company_id from JWT
CREATE OR REPLACE FUNCTION auth.company_id()
RETURNS UUID AS $$
DECLARE
    company_id_val UUID;
BEGIN
    -- This setting is crucial and must be passed from the backend.
    -- Supabase automatically sets this up for requests made with the user's JWT.
    company_id_val := NULLIF(current_setting('request.jwt.claims', true)::JSONB -> 'app_metadata' ->> 'company_id', '')::UUID;
    
    -- Fallback for cases where app_metadata might not be populated yet (e.g., during signup trigger).
    IF company_id_val IS NULL THEN
        SELECT raw_app_meta_data->>'company_id' INTO company_id_val
        FROM auth.users WHERE id = auth.uid();
    END IF;

    RETURN company_id_val;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- Main Tables

CREATE TABLE IF NOT EXISTS public.companies (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    owner_id uuid REFERENCES auth.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_users (
    company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE NOT NULL,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    role public.company_role DEFAULT 'Member'::public.company_role NOT NULL,
    PRIMARY KEY (company_id, user_id)
);


CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    overstock_multiplier integer NOT NULL DEFAULT 3,
    high_value_threshold integer NOT NULL DEFAULT 100000,
    alert_settings jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone
);


CREATE TABLE IF NOT EXISTS public.products (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    UNIQUE (company_id, external_product_id)
);


CREATE TABLE IF NOT EXISTS public.product_variants (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer NOT NULL DEFAULT 0,
    location text,
    reorder_point integer,
    reorder_quantity integer,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    UNIQUE (company_id, sku),
    UNIQUE (company_id, external_variant_id)
);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.customers (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    UNIQUE (company_id, email),
    UNIQUE (company_id, external_customer_id)
);


CREATE TABLE IF NOT EXISTS public.orders (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal integer NOT NULL DEFAULT 0,
    total_tax integer,
    total_shipping integer,
    total_discounts integer,
    total_amount integer NOT NULL,
    source_platform text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    UNIQUE (company_id, external_order_id)
);


CREATE TABLE IF NOT EXISTS public.order_line_items (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_name text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer,
    tax_amount integer,
    cost_at_time integer,
    external_line_item_id text,
    UNIQUE (order_id, external_line_item_id)
);

-- RLS Policies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read their own company" ON public.companies;
CREATE POLICY "Users can read their own company" ON public.companies FOR SELECT USING (id = auth.company_id());

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company settings" ON public.company_settings;
CREATE POLICY "Users can manage their own company settings" ON public.company_settings FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view members of their own company" ON public.company_users;
CREATE POLICY "Users can view members of their own company" ON public.company_users FOR SELECT USING (company_id = auth.company_id());

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's products" ON public.products;
CREATE POLICY "Users can manage their own company's products" ON public.products FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's variants" ON public.product_variants;
CREATE POLICY "Users can manage their own company's variants" ON public.product_variants FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's suppliers" ON public.suppliers;
CREATE POLICY "Users can manage their own company's suppliers" ON public.suppliers FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's customers" ON public.customers;
CREATE POLICY "Users can manage their own company's customers" ON public.customers FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's orders" ON public.orders;
CREATE POLICY "Users can manage their own company's orders" ON public.orders FOR ALL USING (company_id = auth.company_id());

ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can manage their own company's line items" ON public.order_line_items;
CREATE POLICY "Users can manage their own company's line items" ON public.order_line_items FOR ALL USING (company_id = auth.company_id());


-- Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_orders_company_created ON public.orders(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON public.order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON public.order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON public.product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON public.product_variants(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_products_company_id ON public.products(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);

-- Materialized Views for Analytics
CREATE MATERIALIZED VIEW IF NOT EXISTS public.customers_view AS
SELECT
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    COUNT(o.id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    MIN(o.created_at) AS first_order_date,
    c.created_at
FROM
    public.customers c
LEFT JOIN
    public.orders o ON c.id = o.customer_id
WHERE c.deleted_at IS NULL
GROUP BY
    c.id;

CREATE UNIQUE INDEX IF NOT EXISTS customers_view_pkey ON public.customers_view(id);

-- Add other tables and schema definitions here as needed...

-- Full-featured Dashboard Metrics Function
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    metrics jsonb;
    range_start timestamp with time zone;
    previous_range_start timestamp with time zone;
BEGIN
    range_start := now() - (p_days || ' days')::interval;
    previous_range_start := range_start - (p_days || ' days')::interval;

    WITH current_period AS (
        SELECT
            COALESCE(SUM(total_amount), 0) AS total_revenue,
            COUNT(*) AS total_orders,
            COUNT(DISTINCT customer_id) AS new_customers
        FROM orders
        WHERE company_id = p_company_id AND created_at >= range_start
    ), previous_period AS (
        SELECT
            COALESCE(SUM(total_amount), 0) AS total_revenue,
            COUNT(*) AS total_orders,
            COUNT(DISTINCT customer_id) AS new_customers
        FROM orders
        WHERE company_id = p_company_id AND created_at >= previous_range_start AND created_at < range_start
    ), inventory AS (
        SELECT
            COALESCE(SUM(cost * inventory_quantity), 0) as total_value,
            COALESCE(SUM(CASE WHEN inventory_quantity > reorder_point THEN cost * inventory_quantity ELSE 0 END), 0) as in_stock_value,
            COALESCE(SUM(CASE WHEN inventory_quantity <= reorder_point AND inventory_quantity > 0 THEN cost * inventory_quantity ELSE 0 END), 0) as low_stock_value
        FROM product_variants
        WHERE company_id = p_company_id
    ), dead_stock as (
        SELECT COALESCE(SUM(total_value), 0) as dead_stock_value FROM get_dead_stock_report(p_company_id)
    ), sales_series as (
        SELECT jsonb_agg(
            jsonb_build_object('date', to_char(d.day, 'YYYY-MM-DD'), 'revenue', d.revenue) ORDER BY d.day
        ) as data
        FROM (
            SELECT date_trunc('day', created_at) AS day, SUM(total_amount) AS revenue
            FROM orders
            WHERE company_id = p_company_id AND created_at >= range_start
            GROUP BY 1
        ) d
    ), top_products as (
        SELECT jsonb_agg(p.product_data) as data
        FROM (
            SELECT
                jsonb_build_object(
                    'product_name', pv.product_title,
                    'image_url', pv.image_url,
                    'total_revenue', SUM(oli.price * oli.quantity),
                    'quantity_sold', SUM(oli.quantity)
                ) as product_data
            FROM order_line_items oli
            JOIN product_variants_with_details pv ON oli.variant_id = pv.id
            WHERE oli.company_id = p_company_id AND oli.created_at >= range_start
            GROUP BY pv.product_title, pv.image_url
            ORDER BY SUM(oli.price * oli.quantity) DESC
            LIMIT 5
        ) p
    )
    SELECT jsonb_build_object(
        'total_revenue', cp.total_revenue,
        'revenue_change', (CASE WHEN pp.total_revenue > 0 THEN ((cp.total_revenue - pp.total_revenue) / pp.total_revenue) * 100 ELSE 0 END),
        'total_orders', cp.total_orders,
        'orders_change', (CASE WHEN pp.total_orders > 0 THEN ((cp.total_orders - pp.total_orders) / pp.total_orders::float) * 100 ELSE 0 END),
        'new_customers', cp.new_customers,
        'customers_change', (CASE WHEN pp.new_customers > 0 THEN ((cp.new_customers - pp.new_customers) / pp.new_customers::float) * 100 ELSE 0 END),
        'dead_stock_value', ds.dead_stock_value,
        'sales_over_time', ss.data,
        'top_selling_products', tp.data,
        'inventory_summary', jsonb_build_object(
            'total_value', inv.total_value,
            'in_stock_value', inv.in_stock_value,
            'low_stock_value', inv.low_stock_value,
            'dead_stock_value', ds.dead_stock_value
        )
    )
    INTO metrics
    FROM current_period cp, previous_period pp, inventory inv, dead_stock ds, sales_series ss, top_products tp;
    
    RETURN metrics;
END;
$$;
