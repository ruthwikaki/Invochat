
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Use pg_graphql for easier API generation.
CREATE EXTENSION IF NOT EXISTS "pg_graphql";

-- Enable PostGIS for potential location-based features.
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Enable Vault for securely storing API keys.
CREATE EXTENSION IF NOT EXISTS "supabase_vault";


--------------------------------------------------------------------------------
-- TYPES
--------------------------------------------------------------------------------
-- These composite types are used as return types for complex functions.

-- For sales velocity report
DROP TYPE IF EXISTS sales_velocity_result;
CREATE TYPE sales_velocity_result AS (
  slow_sellers JSON,
  fast_sellers JSON
);

-- For ABC Analysis report
DROP TYPE IF EXISTS abc_analysis_result;
CREATE TYPE abc_analysis_result AS (
  category_a JSON,
  category_b JSON,
  category_c JSON,
  analysis_summary JSON
);

-- For inventory analytics card on the inventory page
DROP TYPE IF EXISTS inventory_analytics_result;
CREATE TYPE inventory_analytics_result AS (
  total_inventory_value NUMERIC,
  total_skus BIGINT,
  low_stock_items BIGINT,
  potential_profit NUMERIC
);

-- For sales analytics card on the sales page
DROP TYPE IF EXISTS sales_analytics_result;
CREATE TYPE sales_analytics_result AS (
    total_revenue BIGINT,
    average_sale_value NUMERIC,
    payment_method_distribution JSON
);

-- For customer analytics on the customers page
DROP TYPE IF EXISTS customer_analytics_result;
CREATE TYPE customer_analytics_result AS (
    total_customers BIGINT,
    new_customers_last_30_days BIGINT,
    repeat_customer_rate NUMERIC,
    average_lifetime_value NUMERIC,
    top_customers_by_spend JSON,
    top_customers_by_sales JSON
);

-- For customer segmentation report
DROP TYPE IF EXISTS customer_segment_analysis_item;
CREATE TYPE customer_segment_analysis_item as (
    segment TEXT,
    sku TEXT,
    product_name TEXT,
    total_quantity BIGINT,
    total_revenue BIGINT
);

-- For inventory aging report
DROP TYPE IF EXISTS inventory_aging_report_item;
CREATE TYPE inventory_aging_report_item AS (
  sku TEXT,
  product_name TEXT,
  quantity BIGINT,
  total_value NUMERIC,
  days_since_last_sale INT
);

-- For product lifecycle analysis
DROP TYPE IF EXISTS product_lifecycle_stage;
CREATE TYPE product_lifecycle_stage AS (
    sku TEXT,
    product_name TEXT,
    stage TEXT,
    total_revenue BIGINT,
    monthly_sales_trend NUMERIC
);

DROP TYPE IF EXISTS product_lifecycle_analysis_result;
CREATE TYPE product_lifecycle_analysis_result AS (
    summary JSON,
    products JSON
);

-- For inventory risk report
DROP TYPE IF EXISTS inventory_risk_item;
CREATE TYPE inventory_risk_item AS (
    sku TEXT,
    product_name TEXT,
    risk_score INT,
    risk_level TEXT,
    total_value NUMERIC,
    reason TEXT
);


--------------------------------------------------------------------------------
-- TABLES
--------------------------------------------------------------------------------

-- Stores company information.
CREATE TABLE IF NOT EXISTS public.companies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Extends Supabase's auth.users table with company and role info.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.companies(id);
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS role TEXT;


-- Stores company-specific settings and business rules.
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id UUID PRIMARY KEY REFERENCES public.companies(id),
  dead_stock_days INT NOT NULL DEFAULT 90,
  fast_moving_days INT NOT NULL DEFAULT 30,
  overstock_multiplier INT NOT NULL DEFAULT 3,
  high_value_threshold INT NOT NULL DEFAULT 100000,
  promo_sales_lift_multiplier NUMERIC NOT NULL DEFAULT 2.5,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

-- Stores supplier information.
CREATE TABLE IF NOT EXISTS public.suppliers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  default_lead_time_days INT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE(company_id, name)
);

-- Stores core product information.
CREATE TABLE IF NOT EXISTS public.inventory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  sku TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT,
  price INT, -- in cents
  cost INT,  -- in cents
  quantity INT NOT NULL DEFAULT 0,
  reorder_point INT,
  reorder_quantity INT,
  supplier_id UUID REFERENCES public.suppliers(id),
  barcode TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  deleted_by UUID REFERENCES auth.users(id),
  source_platform TEXT,
  external_product_id TEXT,
  external_variant_id TEXT,
  external_quantity INT,
  last_sync_at TIMESTAMPTZ,
  UNIQUE(company_id, sku)
);

-- Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    customer_name TEXT NOT NULL,
    email TEXT,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, email)
);

-- Stores sales transaction headers.
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    user_id UUID REFERENCES auth.users(id),
    customer_id UUID REFERENCES public.customers(id),
    sale_number TEXT NOT NULL,
    total_amount INT NOT NULL, -- in cents
    payment_method TEXT,
    notes TEXT,
    external_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, external_id)
);


-- Stores individual line items for each sale.
CREATE TABLE IF NOT EXISTS public.sale_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES public.sales(id),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    product_id UUID NOT NULL REFERENCES public.inventory(id),
    quantity INT NOT NULL,
    unit_price INT NOT NULL, -- in cents
    cost_at_time INT, -- in cents
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- A detailed log of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id BIGSERIAL PRIMARY KEY,
    company_id UUID NOT NULL REFERENCES public.companies(id),
    product_id UUID NOT NULL REFERENCES public.inventory(id),
    change_type TEXT NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., sale_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Stores jobs for data exports.
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    requested_by_user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Stores logs for e-commerce integration syncs.
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id BIGSERIAL PRIMARY KEY,
    integration_id UUID NOT NULL,
    sync_type TEXT NOT NULL, -- e.g., 'products', 'sales'
    status TEXT NOT NULL, -- e.g., 'started', 'completed', 'failed'
    records_synced INT,
    error_message TEXT,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Stores the state of an ongoing sync to allow for resumption.
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id UUID NOT NULL,
    sync_type TEXT NOT NULL,
    last_processed_cursor TEXT,
    last_update TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (integration_id, sync_type)
);

-- Stores integration credentials and settings.
CREATE TABLE IF NOT EXISTS public.integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL REFERENCES public.companies(id),
  platform TEXT NOT NULL,
  shop_domain TEXT,
  shop_name TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  last_sync_at TIMESTAMPTZ,
  sync_status TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  UNIQUE (company_id, platform)
);

-- Stores sales channel fees for net margin calculations.
CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC NOT NULL,
    fixed_fee INT NOT NULL, -- in cents
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE(company_id, channel_name)
);

-- Stores user feedback on AI features.
CREATE TABLE IF NOT EXISTS public.audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    action TEXT NOT NULL,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- INDEXES
--------------------------------------------------------------------------------
-- These indexes are crucial for performance, especially on tables that are
-- frequently queried with 'where' clauses.

CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory (company_id);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales (company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items (sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON public.sale_items (product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger (product_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers (company_id, email);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers (company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_supplier_id ON public.inventory (supplier_id);


--------------------------------------------------------------------------------
-- FUNCTIONS AND TRIGGERS
--------------------------------------------------------------------------------

-- Function to create a company and settings for a new user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_company_id UUID;
  user_role TEXT;
BEGIN
  -- Determine role based on metadata, default to 'Owner'
  user_role := COALESCE(new.raw_user_meta_data->>'role', 'Owner');

  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id, promo_sales_lift_multiplier)
  VALUES (new_company_id, 2.5);

  -- Update the user's metadata with the new company ID and role
  UPDATE auth.users
  SET
    app_metadata = jsonb_set(
        jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
        '{role}', to_jsonb(user_role)
    ),
    role = user_role -- Also set the top-level role column
  WHERE id = new.id;
  RETURN new;
END;
$$;

-- Trigger to execute the function when a new user is created.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to update inventory ledger after an inventory change.
CREATE OR REPLACE FUNCTION public.log_inventory_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.inventory_ledger(company_id, product_id, change_type, quantity_change, new_quantity, notes)
    VALUES (NEW.company_id, NEW.id, 'adjustment', NEW.quantity - OLD.quantity, NEW.quantity, 'Manual update');
    RETURN NEW;
END;
$$;

-- Trigger for inventory adjustments.
DROP TRIGGER IF EXISTS inventory_update_trigger ON public.inventory;
CREATE TRIGGER inventory_update_trigger
AFTER UPDATE OF quantity ON public.inventory
FOR EACH ROW
WHEN (OLD.quantity IS DISTINCT FROM NEW.quantity)
EXECUTE FUNCTION public.log_inventory_change();


-- Main transaction function for recording a sale.
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_sale_items JSONB,
    p_customer_name TEXT DEFAULT NULL,
    p_customer_email TEXT DEFAULT NULL,
    p_payment_method TEXT DEFAULT 'other',
    p_notes TEXT DEFAULT NULL,
    p_external_id TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    new_sale_id UUID;
    new_customer_id UUID;
    total_sale_amount INT := 0;
    item RECORD;
    inv_record RECORD;
    new_sale_number TEXT;
BEGIN
    -- Step 1: Find or create customer
    IF p_customer_email IS NOT NULL THEN
        SELECT id INTO new_customer_id FROM public.customers
        WHERE company_id = p_company_id AND email = p_customer_email;

        IF new_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, customer_name, email)
            VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email)
            RETURNING id INTO new_customer_id;
        END IF;
    END IF;

    -- Step 2: Calculate total and check inventory
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id UUID, quantity INT, unit_price INT, cost_at_time INT)
    LOOP
        SELECT quantity, cost INTO inv_record FROM public.inventory WHERE id = item.product_id AND company_id = p_company_id;
        IF NOT FOUND OR inv_record.quantity < item.quantity THEN
            RAISE EXCEPTION 'Not enough stock for product ID %', item.product_id;
        END IF;
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Step 3: Create sale record
    SELECT 'SALE-' || TO_CHAR(NOW(), 'YYMMDD') || '-' || LPAD(nextval('sale_number_seq')::TEXT, 4, '0') INTO new_sale_number;

    INSERT INTO public.sales (company_id, user_id, customer_id, sale_number, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, p_user_id, new_customer_id, new_sale_number, total_sale_amount, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Step 4: Create sale items and update inventory
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id UUID, quantity INT, unit_price INT, cost_at_time INT)
    LOOP
        SELECT cost INTO inv_record FROM public.inventory WHERE id = item.product_id AND company_id = p_company_id;

        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, item.product_id, item.quantity, item.unit_price, COALESCE(item.cost_at_time, inv_record.cost));

        UPDATE public.inventory SET quantity = quantity - item.quantity WHERE id = item.product_id;

        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        SELECT p_company_id, item.product_id, 'sale', -item.quantity, i.quantity, new_sale_id
        FROM public.inventory i WHERE i.id = item.product_id;
    END LOOP;

    RETURN json_build_object('sale_id', new_sale_id, 'sale_number', new_sale_number);
END;
$$;

-- Sequence for generating unique sale numbers.
CREATE SEQUENCE IF NOT EXISTS sale_number_seq START 1;


-- Function to get distinct product categories for a company.
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id UUID)
RETURNS TABLE(category TEXT)
LANGUAGE sql STABLE
AS $$
    SELECT DISTINCT category
    FROM public.inventory
    WHERE company_id = p_company_id AND category IS NOT NULL AND category != ''
    ORDER BY category;
$$;


-- Function to get customer stats.
CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id UUID,
    p_query TEXT,
    p_limit INT,
    p_offset INT
)
RETURNS TABLE (items JSON, total_count BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH filtered_customers AS (
        SELECT * FROM public.customers c
        WHERE c.company_id = p_company_id
        AND c.deleted_at IS NULL
        AND (p_query IS NULL OR (c.customer_name ILIKE '%' || p_query || '%' OR c.email ILIKE '%' || p_query || '%'))
    )
    SELECT
        (SELECT json_agg(t) FROM (
            SELECT
                fc.id,
                fc.customer_name,
                fc.email,
                fc.created_at,
                COUNT(s.id) as total_orders,
                COALESCE(SUM(s.total_amount), 0) as total_spent
            FROM filtered_customers fc
            LEFT JOIN public.sales s ON fc.id = s.customer_id
            GROUP BY fc.id, fc.customer_name, fc.email, fc.created_at
            ORDER BY fc.customer_name
            LIMIT p_limit OFFSET p_offset
        ) t) as items,
        (SELECT COUNT(*) FROM filtered_customers) as total_count;
END;
$$;


-- Function to get paginated inventory with supplier names.
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id UUID,
    p_query TEXT,
    p_category TEXT,
    p_supplier_id UUID,
    p_sku_filter TEXT[],
    p_limit INT,
    p_offset INT
)
RETURNS TABLE (items JSON, total_count BIGINT)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH filtered_inventory AS (
        SELECT i.* FROM public.inventory i
        WHERE i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR i.category = p_category)
        AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
        AND (p_sku_filter IS NULL OR i.sku = ANY(p_sku_filter))
    )
    SELECT
        (SELECT json_agg(t) FROM (
            SELECT
                fi.id as product_id,
                fi.sku,
                fi.name as product_name,
                fi.category,
                fi.quantity,
                fi.cost,
                fi.price,
                fi.quantity * fi.cost as total_value,
                fi.reorder_point,
                s.name as supplier_name,
                fi.supplier_id,
                fi.barcode
            FROM filtered_inventory fi
            LEFT JOIN public.suppliers s ON fi.supplier_id = s.id
            ORDER BY fi.name
            LIMIT p_limit OFFSET p_offset
        ) t) as items,
        (SELECT COUNT(*) FROM filtered_inventory) as total_count;
END;
$$;

--------------------------------------------------------------------------------
-- ANALYTICS FUNCTIONS
--------------------------------------------------------------------------------

-- Function for customer segmentation report.
DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id UUID)
RETURNS SETOF customer_segment_analysis_item
LANGUAGE sql STABLE
AS $$
WITH customer_stats AS (
    SELECT
        c.email,
        COUNT(s.id) AS order_count,
        SUM(s.total_amount) AS total_spend
    FROM public.customers c
    JOIN public.sales s ON c.email = (SELECT email FROM public.customers WHERE id = s.customer_id)
    WHERE c.company_id = p_company_id AND c.email IS NOT NULL
    GROUP BY c.email
),
ranked_customers AS (
    SELECT *,
    NTILE(10) OVER (ORDER BY total_spend DESC) as decile
    FROM customer_stats
),
segments AS (
    SELECT
        email,
        CASE
            WHEN order_count = 1 THEN 'New Customers'
            ELSE 'Repeat Customers'
        END AS segment
    FROM customer_stats
    UNION ALL
    SELECT
        email,
        'Top Spenders' AS segment
    FROM ranked_customers
    WHERE decile = 1
),
segment_sales AS (
    SELECT
        s.segment,
        si.product_id,
        SUM(si.quantity) as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM segments s
    JOIN public.sales sa ON sa.customer_id = (SELECT id FROM public.customers WHERE email = s.email AND company_id = p_company_id)
    JOIN public.sale_items si ON si.sale_id = sa.id
    WHERE sa.company_id = p_company_id
    GROUP BY s.segment, si.product_id
)
SELECT
    ss.segment,
    i.sku,
    i.name as product_name,
    ss.total_quantity,
    ss.total_revenue
FROM segment_sales ss
JOIN public.inventory i ON i.id = ss.product_id
ORDER BY ss.segment, ss.total_revenue DESC;
$$;

-- Function for demand forecasting.
DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id UUID)
RETURNS TABLE (sku TEXT, product_name TEXT, forecast_demand BIGINT)
LANGUAGE sql
AS $$
WITH monthly_sales AS (
    SELECT
        i.sku,
        i.name as product_name,
        date_trunc('month', s.created_at) as sale_month,
        SUM(si.quantity) as total_quantity
    FROM public.inventory i
    JOIN public.sale_items si ON i.id = si.product_id
    JOIN public.sales s ON si.sale_id = s.id
    WHERE i.company_id = p_company_id
      AND s.created_at >= NOW() - INTERVAL '12 months'
    GROUP BY 1, 2, 3
),
ewma_sales AS (
    SELECT
        sku,
        product_name,
        sale_month,
        total_quantity,
        -- Calculate EWMA with alpha = 0.3
        AVG(total_quantity) OVER (PARTITION BY sku ORDER BY sale_month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 0.3
        +
        COALESCE(LAG(AVG(total_quantity) OVER (PARTITION BY sku ORDER BY sale_month), 1, total_quantity) OVER (PARTITION BY sku ORDER BY sale_month), total_quantity) * 0.7
        AS ewma_quantity
    FROM monthly_sales
),
latest_ewma AS (
  SELECT *,
  ROW_NUMBER() OVER(PARTITION BY sku ORDER BY sale_month DESC) as rn
  FROM ewma_sales
)
SELECT
    le.sku,
    le.product_name,
    CEIL(le.ewma_quantity)::BIGINT as forecast_demand
FROM latest_ewma le
WHERE le.rn = 1
ORDER BY le.ewma_quantity DESC
LIMIT 10;
$$;


-- Function for promotional impact analysis.
DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id UUID,
    p_skus TEXT[],
    p_discount_percentage NUMERIC,
    p_duration_days INT
)
RETURNS TABLE(
    estimated_sales_lift_units BIGINT,
    estimated_additional_revenue NUMERIC,
    estimated_additional_profit NUMERIC,
    estimated_roi NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sales_lift_multiplier NUMERIC;
    v_total_base_units BIGINT;
    v_total_base_revenue NUMERIC;
    v_total_base_profit NUMERIC;
BEGIN
    -- Get the configurable sales lift multiplier from settings
    SELECT cs.promo_sales_lift_multiplier
    INTO v_sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- Calculate base performance
    SELECT
        COALESCE(SUM(si.quantity), 0),
        COALESCE(SUM(si.quantity * si.unit_price), 0),
        COALESCE(SUM(si.quantity * (si.unit_price - si.cost_at_time)), 0)
    INTO v_total_base_units, v_total_base_revenue, v_total_base_profit
    FROM public.sale_items si
    JOIN public.inventory i ON si.product_id = i.id
    JOIN public.sales s ON si.sale_id = s.id
    WHERE i.company_id = p_company_id
      AND i.sku = ANY(p_skus)
      AND s.created_at >= NOW() - (p_duration_days || ' days')::INTERVAL;

    -- A more realistic sales lift formula that models diminishing returns
    -- A 20% discount might give a 2x lift, but a 90% discount won't give a 5.5x lift.
    -- This uses a sigmoid-like curve shape.
    estimated_sales_lift_units := CEIL(v_total_base_units * (1 + (v_sales_lift_multiplier - 1) * (1 - exp(-p_discount_percentage * 5))));

    estimated_additional_revenue := (estimated_sales_lift_units * (v_total_base_revenue / GREATEST(v_total_base_units, 1)) * (1 - p_discount_percentage)) - v_total_base_revenue;

    estimated_additional_profit := (estimated_sales_lift_units * ((v_total_base_revenue / GREATEST(v_total_base_units, 1)) * (1 - p_discount_percentage) - (v_total_base_profit / GREATEST(v_total_base_units, 1)))) - v_total_base_profit;

    estimated_roi := CASE
        WHEN (v_total_base_profit - (estimated_sales_lift_units * ((v_total_base_revenue / GREATEST(v_total_base_units, 1)) * p_discount_percentage))) > 0
        THEN estimated_additional_profit / (v_total_base_profit - (estimated_sales_lift_units * ((v_total_base_revenue / GREATEST(v_total_base_units, 1)) * p_discount_percentage)))
        ELSE 0
    END;

    RETURN NEXT;
END;
$$;


-- Grant usage on the auth schema to postgres role
GRANT USAGE ON SCHEMA auth TO postgres;
GRANT SELECT ON auth.users TO postgres;

    