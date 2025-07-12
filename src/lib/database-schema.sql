
-- Enable the UUID extension if it's not already enabled.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant usage on the auth schema to the postgres role
GRANT USAGE ON SCHEMA auth TO postgres;

-- Define a custom user role type
CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

-- Companies Table: Stores basic information about each company using the service.
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Users Table: Extends the built-in auth.users table with company-specific info.
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    email text,
    role user_role NOT NULL DEFAULT 'Member'::user_role,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Company Settings Table: Configurable business logic rules for each company.
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
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
    stripe_subscription_id text,
    promo_sales_lift_multiplier real NOT NULL DEFAULT 2.5
);

-- Suppliers Table: Information about product suppliers.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(company_id, name)
);

-- Inventory Table: Core table for all product and stock information.
CREATE TABLE IF NOT EXISTS public.inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL,
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
    deleted_at timestamptz,
    deleted_by uuid REFERENCES public.users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    UNIQUE(company_id, sku)
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

-- Inventory Ledger: An append-only log of all stock movements for auditing.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL REFERENCES public.inventory(id) ON DELETE CASCADE,
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    related_id uuid, -- e.g., sale_id, purchase_order_id, etc.
    notes text
);

-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

-- Sales Table: Records each sale transaction.
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number text NOT NULL,
    customer_name text,
    customer_email text,
    total_amount numeric NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    external_id text, -- ID from an external platform like Shopify
    UNIQUE(company_id, sale_number)
);

-- Sale Items Table: Line items for each sale.
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL,
    sku text NOT NULL,
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL,
    cost_at_time numeric,
    FOREIGN KEY (company_id, sku) REFERENCES public.inventory(company_id, sku)
);

-- Conversations Table: Stores chat conversation history.
CREATE TABLE IF NOT EXISTS public.conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

-- Messages Table: Stores individual messages within a conversation.
CREATE TABLE IF NOT EXISTS public.messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
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


-- Integrations table
CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  access_token text, -- This is a placeholder; real tokens should be in a vault
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

-- Sync State table
CREATE TABLE IF NOT EXISTS public.sync_state (
  integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
  sync_type text NOT NULL,
  last_processed_cursor text,
  last_update timestamptz,
  PRIMARY KEY (integration_id, sync_type)
);


-- Channel Fees Table
CREATE TABLE IF NOT EXISTS public.channel_fees (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  channel_name text NOT NULL,
  percentage_fee numeric NOT NULL,
  fixed_fee numeric NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz,
  UNIQUE(company_id, channel_name)
);

-- Sync Logs table
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    sync_type text,
    status text,
    records_synced integer,
    error_message text,
    started_at timestamptz DEFAULT now(),
    completed_at timestamptz
);

-- Export Jobs table
CREATE TABLE IF NOT EXISTS public.export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url TEXT,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Audit Log Table: Tracks significant user and system actions.
CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  details jsonb,
  created_at timestamptz DEFAULT now()
);


-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_inventory_company_id ON public.inventory(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_company_id_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON public.sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_company_sku ON public.sale_items(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_email ON public.customers(company_id, email);


-- Function to handle new user sign-ups
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_app_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert a row into public.users
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Insert default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id, 'role', 'Owner')
  WHERE id = new.id;
  
  RETURN new;
END;
$$;


-- Trigger to call handle_new_user on new user creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function to handle inventory updates and log changes
CREATE OR REPLACE FUNCTION public.handle_inventory_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Log the change to the inventory_ledger
  INSERT INTO public.inventory_ledger(company_id, product_id, change_type, quantity_change, new_quantity, notes)
  VALUES (NEW.company_id, NEW.id, 'adjustment', NEW.quantity - OLD.quantity, NEW.quantity, 'Manual update');

  -- Update the version number
  NEW.version = OLD.version + 1;
  NEW.updated_at = now();
  
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_inventory_update ON public.inventory;
CREATE TRIGGER on_inventory_update
  BEFORE UPDATE ON public.inventory
  FOR EACH ROW
  WHEN (OLD.quantity IS DISTINCT FROM NEW.quantity)
  EXECUTE FUNCTION public.handle_inventory_change();


--------------------------------------------------------------------------------
-- ANALYTICAL FUNCTIONS
--------------------------------------------------------------------------------

-- Function to get distinct categories for a company
DROP FUNCTION IF EXISTS public.get_distinct_categories(uuid);
CREATE OR REPLACE FUNCTION public.get_distinct_categories(p_company_id uuid)
RETURNS TABLE(category text) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT inv.category
  FROM public.inventory inv
  WHERE inv.company_id = p_company_id AND inv.category IS NOT NULL AND inv.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


DROP FUNCTION IF EXISTS public.get_financial_impact_of_promotion(uuid, text[], numeric, integer);
CREATE OR REPLACE FUNCTION public.get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days integer
)
RETURNS TABLE (
    estimated_sales_lift_units numeric,
    estimated_additional_revenue numeric,
    estimated_additional_profit numeric,
    estimated_profit_change_percentage numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    sales_lift_multiplier REAL;
    avg_daily_sales NUMERIC;
    total_cost NUMERIC;
    original_price NUMERIC;
BEGIN
    -- Get the company-specific sales lift multiplier
    SELECT cs.promo_sales_lift_multiplier INTO sales_lift_multiplier
    FROM public.company_settings cs
    WHERE cs.company_id = p_company_id;

    -- Calculate baseline sales and cost for the selected SKUs
    SELECT
        SUM(si.quantity) / 90.0, -- Average daily sales over last 90 days
        SUM(si.quantity * i.cost),
        SUM(si.quantity * i.price)
    INTO
        avg_daily_sales,
        total_cost,
        original_price
    FROM public.sale_items si
    JOIN public.inventory i ON si.sku = i.sku AND si.company_id = i.company_id
    WHERE si.company_id = p_company_id
      AND si.sku = ANY(p_skus)
      AND si.created_at >= (now() - interval '90 days');

    -- Avoid division by zero if no sales
    IF avg_daily_sales IS NULL OR avg_daily_sales = 0 THEN
        estimated_sales_lift_units := 0;
        estimated_additional_revenue := 0;
        estimated_additional_profit := 0;
        estimated_profit_change_percentage := 0;
        RETURN;
    END IF;

    -- Calculate lift using a non-linear model to show diminishing returns
    -- A 20% discount might give a 2x lift, but an 80% discount doesn't give an 8x lift.
    -- We use a logarithmic curve for a more realistic projection.
    estimated_sales_lift_units := avg_daily_sales * p_duration_days * (1 + sales_lift_multiplier * LN(1 + p_discount_percentage * 10));

    -- Calculate revenue and profit
    DECLARE
        discounted_price NUMERIC := original_price * (1 - p_discount_percentage);
        baseline_profit NUMERIC := original_price - total_cost;
        promo_profit NUMERIC := (discounted_price * estimated_sales_lift_units) - (total_cost * estimated_sales_lift_units);
    BEGIN
        estimated_additional_revenue := (discounted_price * estimated_sales_lift_units) - (original_price * avg_daily_sales * p_duration_days);
        estimated_additional_profit := promo_profit - (baseline_profit * avg_daily_sales * p_duration_days);

        IF baseline_profit > 0 THEN
            estimated_profit_change_percentage := (estimated_additional_profit / (baseline_profit * avg_daily_sales * p_duration_days)) * 100;
        ELSE
            estimated_profit_change_percentage := 0;
        END IF;
    END;

    RETURN NEXT;
END;
$$;


DROP FUNCTION IF EXISTS public.get_demand_forecast(uuid);
CREATE OR REPLACE FUNCTION public.get_demand_forecast(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    forecasted_demand numeric
)
SECURITY DEFINER
AS $$
DECLARE
    smoothing_factor CONSTANT double precision := 0.3; -- Alpha for EWMA
BEGIN
    RETURN QUERY
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at) as sale_month,
            SUM(si.quantity) as total_quantity
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
          AND s.created_at >= now() - interval '12 months'
        GROUP BY 1, 2
    ),
    -- Use EWMA to give more weight to recent sales
    ewma_sales AS (
      SELECT
          sku,
          sale_month,
          total_quantity,
          AVG(total_quantity) OVER (
              PARTITION BY sku
              ORDER BY sale_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
          ) as ewma
      FROM monthly_sales
    ),
    latest_forecast AS (
        SELECT
            e.sku,
            MAX(i.name) as product_name,
            -- Forecast for next 30 days is the last EWMA value
            (MAX(e.ewma) FILTER (WHERE e.sale_month = (SELECT MAX(sale_month) FROM ewma_sales es WHERE es.sku = e.sku))) as forecasted_demand
        FROM ewma_sales e
        JOIN public.inventory i ON e.sku = i.sku AND i.company_id = p_company_id
        GROUP BY 1
    )
    SELECT
        lf.sku,
        lf.product_name,
        ROUND(lf.forecasted_demand, 0) as forecasted_demand
    FROM latest_forecast lf
    ORDER BY lf.forecasted_demand DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS public.get_customer_segment_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE(segment text, sku text, product_name text, total_quantity bigint, total_revenue numeric)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    -- New Customers: products bought on their first ever order
    WITH first_orders AS (
        SELECT
            s.customer_email,
            MIN(s.created_at) as first_order_date
        FROM public.sales s
        WHERE s.company_id = p_company_id
          AND s.customer_email IS NOT NULL
        GROUP BY 1
    )
    SELECT
        'New Customers' as segment,
        si.sku,
        si.product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN first_orders fo ON s.customer_email = fo.customer_email AND date_trunc('day', s.created_at) = date_trunc('day', fo.first_order_date)
    WHERE s.company_id = p_company_id
    GROUP BY 1, 2, 3
    ORDER BY total_revenue DESC
    LIMIT 10

    UNION ALL

    -- Repeat Customers: products bought on their 2nd, 3rd, etc. order
    SELECT
        'Repeat Customers' as segment,
        si.sku,
        si.product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    JOIN public.customers c ON s.customer_email = c.email AND s.company_id = c.company_id
    WHERE s.company_id = p_company_id
      AND c.total_orders > 1
    GROUP BY 1, 2, 3
    ORDER BY total_revenue DESC
    LIMIT 10

    UNION ALL

    -- Top Spenders: products bought by the top 10% of customers by total spend
    SELECT
        'Top Spenders' as segment,
        si.sku,
        si.product_name,
        SUM(si.quantity)::bigint as total_quantity,
        SUM(si.quantity * si.unit_price) as total_revenue
    FROM public.sales s
    JOIN public.sale_items si ON s.id = si.sale_id
    WHERE s.company_id = p_company_id
      AND s.customer_email IN (
          SELECT email FROM public.customers
          WHERE company_id = p_company_id
          ORDER BY total_spent DESC
          LIMIT GREATEST(1, (SELECT COUNT(*) * 0.1 FROM public.customers WHERE company_id = p_company_id)::int)
      )
    GROUP BY 1, 2, 3
    ORDER BY total_revenue DESC
    LIMIT 10;
END;
$$;


DROP FUNCTION IF EXISTS public.get_product_lifecycle_analysis(uuid);
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result json;
BEGIN
    WITH monthly_sales AS (
        SELECT
            si.sku,
            date_trunc('month', s.created_at)::date as sale_month,
            sum(si.quantity) as monthly_quantity
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id
        GROUP BY 1, 2
    ),
    sales_with_lags AS (
        SELECT
            sku,
            sale_month,
            monthly_quantity,
            LAG(monthly_quantity, 1, 0) OVER (PARTITION BY sku ORDER BY sale_month) as prev_month_sales,
            LAG(monthly_quantity, 2, 0) OVER (PARTITION BY sku ORDER BY sale_month) as prev_2_month_sales
        FROM monthly_sales
    ),
    product_trends AS (
        SELECT
            i.sku,
            i.name as product_name,
            i.created_at,
            MAX(s.created_at) as last_sale_date,
            SUM(swl.monthly_quantity) as total_sales,
            (
                SUM(CASE WHEN swl.sale_month >= (now() - interval '90 days') THEN swl.monthly_quantity ELSE 0 END)
                - SUM(CASE WHEN swl.sale_month < (now() - interval '90 days') AND swl.sale_month >= (now() - interval '180 days') THEN swl.monthly_quantity ELSE 0 END)
            ) as sales_trend,
            ROW_NUMBER() OVER (PARTITION BY i.sku ORDER BY swl.sale_month DESC) as rn
        FROM public.inventory i
        LEFT JOIN sales_with_lags swl ON i.sku = swl.sku
        LEFT JOIN public.sales s ON i.sku = (SELECT sku FROM public.sale_items si WHERE si.sale_id = s.id LIMIT 1) AND s.company_id = i.company_id
        WHERE i.company_id = p_company_id
        GROUP BY i.id, swl.sale_month
    ),
    -- Use a CTE with ROW_NUMBER() to simulate QUALIFY, which is not in Postgres
    latest_product_trends AS (
        SELECT * FROM product_trends WHERE rn = 1
    ),
    product_stages AS (
        SELECT
            sku,
            product_name,
            total_sales,
            last_sale_date,
            CASE
                WHEN created_at > (now() - interval '60 days') AND total_sales > 0 THEN 'Launch'
                WHEN sales_trend > 0 THEN 'Growth'
                WHEN sales_trend <= 0 AND last_sale_date > (now() - interval '180 days') THEN 'Maturity'
                ELSE 'Decline'
            END as stage,
            (SELECT SUM(si.quantity * si.unit_price) FROM sale_items si JOIN sales s ON si.sale_id = s.id WHERE si.sku = latest_product_trends.sku AND s.company_id = p_company_id) as total_revenue
        FROM latest_product_trends
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
        'products', (SELECT json_agg(ps) FROM product_stages ps)
    ) INTO result
    FROM product_stages
    LIMIT 1;

    RETURN result;
END;
$$;


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
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        -- Suggested quantity is the reorder quantity, or enough to get back to reorder point + a buffer
        COALESCE(i.reorder_quantity, i.reorder_point - i.quantity + (i.reorder_point / 2)) AS suggested_reorder_quantity,
        s.id as supplier_id,
        s.name as supplier_name,
        i.cost as unit_cost
    FROM public.inventory i
    LEFT JOIN public.suppliers s ON i.supplier_id = s.id
    WHERE i.company_id = p_company_id
      AND i.deleted_at IS NULL
      AND i.reorder_point IS NOT NULL
      AND i.quantity < i.reorder_point;
END;
$$ LANGUAGE plpgsql;

-- Grant EXECUTE permission on all functions in the public schema to the service_role
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN (SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
              FROM pg_proc p
              JOIN pg_namespace n ON p.pronamespace = n.oid
              WHERE n.nspname = 'public')
    LOOP
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.' || r.proname || '(' || r.args || ') TO service_role;';
    END LOOP;
END;
$$;
