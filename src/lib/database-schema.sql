
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


-- Create Companies Table
CREATE TABLE IF NOT EXISTS public.companies (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT companies_pkey PRIMARY KEY (id)
);

-- Create Users Table to store app-specific user data
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

-- Create Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer NOT NULL DEFAULT 90,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_at timestamp with time zone,
    CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
    CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Create Suppliers Table
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

-- Create Inventory Table
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
    supplier_id uuid,
    last_sold_date date,
    barcode text,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    CONSTRAINT inventory_pkey PRIMARY KEY (id),
    CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT inventory_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL,
    CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku)
);


-- Create Customers Table
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

-- Create Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL,
    sale_number text NOT NULL,
    customer_id uuid,
    total_amount numeric NOT NULL,
    payment_method text,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    external_id text,
    CONSTRAINT sales_pkey PRIMARY KEY (id),
    CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sales_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
    CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number)
);

-- Create Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL,
    company_id uuid NOT NULL,
    product_id uuid,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL,
    cost_at_time numeric,
    CONSTRAINT sale_items_pkey PRIMARY KEY (id),
    CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.sales(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
    CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE SET NULL
);

-- Create Inventory Ledger Table
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

-- Create Conversations Table
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

-- Create Messages Table
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

-- Create Audit Log Table
CREATE TABLE IF NOT EXISTS public.audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
    user_id uuid,
    company_id uuid,
    action text NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_log_pkey PRIMARY KEY (id),
    CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT audit_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Create Integrations Table
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

-- Create Sync State Table
CREATE TABLE IF NOT EXISTS public.sync_state (
    integration_id uuid NOT NULL,
    sync_type text NOT NULL,
    last_processed_cursor text,
    last_update timestamp with time zone,
    CONSTRAINT sync_state_pkey PRIMARY KEY (integration_id, sync_type),
    CONSTRAINT sync_state_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE
);

-- Create Sync Logs Table
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


-- Create Channel Fees Table
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
    CONSTRAINT channel_fees_company_id_channel_name_key UNIQUE(company_id, channel_name)
);

-- Create Export Jobs Table
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

-- =================================================================
-- Handle New User Function and Trigger
-- This function creates a new company and links it to the new user.
-- =================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name)
  VALUES (NEW.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Insert into our public users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (NEW.id, new_company_id, NEW.email, 'Owner');
  
  -- Insert default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the company_id and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Create the trigger only if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'on_auth_user_created'
    ) THEN
        CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW
        EXECUTE FUNCTION public.handle_new_user();
    END IF;
END$$;


-- =================================================================
-- RLS Policies
-- =================================================================

-- Utility function to get the current user's company_id from their JWT
CREATE OR REPLACE FUNCTION auth.get_my_company_id()
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'company_id')::uuid;
$$;

-- Utility function to get the current user's role from their JWT
CREATE OR REPLACE FUNCTION auth.get_my_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT (auth.jwt()->'app_metadata'->>'role')::text;
$$;

-- Generic function to enable RLS and apply a company-based policy
CREATE OR REPLACE PROCEDURE enable_rls_for_table(p_table_name text)
LANGUAGE plpgsql
AS $$
BEGIN
    EXECUTE 'ALTER TABLE public.' || quote_ident(p_table_name) || ' ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Users can only see their own company''s data." ON public.' || quote_ident(p_table_name);
    EXECUTE 'CREATE POLICY "Users can only see their own company''s data." ON public.' || quote_ident(p_table_name) ||
            ' FOR ALL USING (company_id = auth.get_my_company_id()) WITH CHECK (company_id = auth.get_my_company_id())';
END;
$$;

-- Apply RLS to all company-scoped tables
CALL enable_rls_for_table('inventory');
CALL enable_rls_for_table('suppliers');
CALL enable_rls_for_table('sales');
CALL enable_rls_for_table('sale_items');
CALL enable_rls_for_table('inventory_ledger');
CALL enable_rls_for_table('customers');
CALL enable_rls_for_table('conversations');
CALL enable_rls_for_table('messages');
CALL enable_rls_for_table('integrations');
CALL enable_rls_for_table('channel_fees');
CALL enable_rls_for_table('export_jobs');
CALL enable_rls_for_table('audit_log');

-- Special RLS for company_settings
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can access their own company settings" ON public.company_settings;
CREATE POLICY "Users can access their own company settings" ON public.company_settings
FOR ALL USING (company_id = auth.get_my_company_id());

-- Special RLS for users table
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view other users in their company" ON public.users;
CREATE POLICY "Users can view other users in their company" ON public.users
FOR SELECT USING (company_id = auth.get_my_company_id());

-- =================================================================
-- Stored Procedures for business logic
-- =================================================================

-- Procedure to refresh materialized views
CREATE OR REPLACE PROCEDURE public.refresh_materialized_views(p_company_id uuid)
LANGUAGE plpgsql
AS $$
BEGIN
    -- This procedure is a placeholder. You would add refresh commands here, e.g.:
    -- REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
END;
$$;


-- Function to get unified inventory data with search and filter
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_sku_filter text DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH filtered_inventory AS (
        SELECT i.*
        FROM public.inventory i
        WHERE i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR i.category = p_category)
        AND (p_supplier_id IS NULL OR i.supplier_id = p_supplier_id)
        AND (p_sku_filter IS NULL OR i.sku = p_sku_filter)
    ),
    counted_inventory AS (
        SELECT *, COUNT(*) OVER() as count
        FROM filtered_inventory
    )
    SELECT
        (SELECT json_agg(
            json_build_object(
                'product_id', ci.id,
                'sku', ci.sku,
                'product_name', ci.name,
                'category', ci.category,
                'quantity', ci.quantity,
                'cost', ci.cost,
                'price', ci.price,
                'total_value', (ci.quantity * ci.cost),
                'reorder_point', ci.reorder_point,
                'supplier_name', s.name,
                'supplier_id', s.id,
                'barcode', ci.barcode
            )
        )
        FROM (
            SELECT ci.*
            FROM counted_inventory ci
            LEFT JOIN public.suppliers s ON ci.supplier_id = s.id
            ORDER BY ci.name
            LIMIT p_limit
            OFFSET p_offset
        ) as ci),
        (SELECT count FROM counted_inventory LIMIT 1);
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
    item record;
    inv_item public.inventory;
    total_sale_amount numeric := 0;
    new_customer_id uuid;
BEGIN
    -- Upsert customer and get ID
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email, first_order_date)
        VALUES (p_company_id, COALESCE(p_customer_name, 'New Customer'), p_customer_email, NOW())
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- Create the sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (
        p_company_id,
        'SALE-' || to_char(NOW(), 'YYYYMMDD-HH24MISS') || '-' || (RANDOM() * 1000)::int,
        new_customer_id,
        0, -- Placeholder, will be updated
        p_payment_method,
        p_notes,
        p_external_id
    ) RETURNING * INTO new_sale;

    -- Loop through sale items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(product_id uuid, quantity int, unit_price numeric)
    LOOP
        -- Get current inventory details
        SELECT * INTO inv_item FROM public.inventory WHERE id = item.product_id AND company_id = p_company_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product with ID % not found.', item.product_id;
        END IF;

        IF inv_item.quantity < item.quantity THEN
            RAISE EXCEPTION 'Not enough stock for product ID %. Available: %, Requested: %', item.product_id, inv_item.quantity, item.quantity;
        END IF;

        -- Insert into sale_items
        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, item.product_id, item.quantity, item.unit_price, inv_item.cost);

        -- Update inventory ledger
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, item.product_id, 'sale', -item.quantity, inv_item.quantity - item.quantity, new_sale.id, 'Sale #' || new_sale.sale_number);

        -- Update inventory quantity
        UPDATE public.inventory
        SET quantity = quantity - item.quantity,
            last_sold_date = NOW()
        WHERE id = item.product_id;

        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- Update the total amount on the sale
    UPDATE public.sales
    SET total_amount = total_sale_amount
    WHERE id = new_sale.id
    RETURNING * INTO new_sale;
    
    -- Update customer stats
    IF new_customer_id IS NOT NULL THEN
        UPDATE public.customers
        SET total_orders = total_orders + 1,
            total_spent = total_spent + total_sale_amount
        WHERE id = new_customer_id;
    END IF;

    RETURN new_sale;
END;
$$;


-- =================================================================
-- Analytics Functions
-- =================================================================

-- Function to get inventory aging report
CREATE OR REPLACE FUNCTION public.get_inventory_aging_report(p_company_id uuid)
RETURNS TABLE(
    sku text,
    product_name text,
    quantity int,
    total_value numeric,
    days_since_last_sale int
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.sku,
        i.name as product_name,
        i.quantity,
        (i.quantity * i.cost) as total_value,
        (CASE
            WHEN i.last_sold_date IS NOT NULL THEN (CURRENT_DATE - i.last_sold_date)
            ELSE (CURRENT_DATE - i.created_at::date)
        END)::int as days_since_last_sale
    FROM public.inventory i
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    ORDER BY days_since_last_sale DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get inventory risk report
CREATE OR REPLACE FUNCTION public.get_inventory_risk_report(p_company_id uuid)
RETURNS TABLE (
    sku text,
    product_name text,
    risk_score int,
    risk_level text,
    total_value numeric,
    reason text
) AS $$
DECLARE
    avg_turnover numeric;
    high_value_thresh numeric;
BEGIN
    SELECT AVG((CURRENT_DATE - created_at::date)::numeric / NULLIF(quantity, 0))
    INTO avg_turnover
    FROM public.inventory
    WHERE company_id = p_company_id AND quantity > 0 AND last_sold_date IS NOT NULL;
    
    SELECT high_value_threshold INTO high_value_thresh FROM public.company_settings WHERE company_id = p_company_id;

    RETURN QUERY
    WITH risk_factors AS (
        SELECT
            i.sku,
            i.name as product_name,
            (i.quantity * i.cost) as total_value,
            -- Factor 1: Age of inventory (max 40 points)
            (LEAST((CURRENT_DATE - COALESCE(i.last_sold_date, i.created_at::date)) / 180.0, 1.0) * 40) as age_score,
            -- Factor 2: Excess stock (max 30 points)
            (LEAST(i.quantity / NULLIF(i.reorder_point, 0) / 5.0, 1.0) * 30) as excess_stock_score,
            -- Factor 3: High value (max 30 points)
            (CASE WHEN i.cost > high_value_thresh THEN 30 ELSE (i.cost / high_value_thresh) * 20 END) as value_score
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    )
    SELECT
        rf.sku,
        rf.product_name,
        (COALESCE(rf.age_score, 0) + COALESCE(rf.excess_stock_score, 0) + COALESCE(rf.value_score, 0))::int as risk_score,
        CASE
            WHEN (COALESCE(rf.age_score, 0) + COALESCE(rf.excess_stock_score, 0) + COALESCE(rf.value_score, 0)) > 75 THEN 'High'
            WHEN (COALESCE(rf.age_score, 0) + COALESCE(rf.excess_stock_score, 0) + COALESCE(rf.value_score, 0)) > 50 THEN 'Medium'
            ELSE 'Low'
        END as risk_level,
        rf.total_value,
        'Age: ' || round(COALESCE(rf.age_score, 0)) || ', Excess: ' || round(COALESCE(rf.excess_stock_score, 0)) || ', Value: ' || round(COALESCE(rf.value_score, 0)) as reason
    FROM risk_factors rf
    ORDER BY risk_score DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to analyze customer segments
CREATE OR REPLACE FUNCTION public.get_customer_segment_analysis(p_company_id uuid)
RETURNS TABLE (
    segment text,
    sku text,
    product_name text,
    total_quantity numeric,
    total_revenue numeric
) AS $$
BEGIN
    RETURN QUERY
    WITH customer_segments AS (
        SELECT
            c.id as customer_id,
            CASE
                WHEN c.total_orders = 1 THEN 'New Customers'
                WHEN c.total_orders > 1 THEN 'Repeat Customers'
            END as segment
        FROM public.customers c
        WHERE c.company_id = p_company_id
        UNION ALL
        SELECT
            c.id as customer_id,
            'Top Spenders' as segment
        FROM public.customers c
        WHERE c.company_id = p_company_id
        ORDER BY c.total_spent DESC
        LIMIT (SELECT COUNT(*) FROM public.customers WHERE company_id = p_company_id) * 0.2 -- Top 20%
    ),
    product_sales AS (
        SELECT
            s.customer_id,
            si.product_id,
            si.quantity,
            si.unit_price
        FROM public.sales s
        JOIN public.sale_items si ON s.id = si.sale_id
        WHERE s.company_id = p_company_id AND s.customer_id IS NOT NULL
    )
    SELECT
        cs.segment,
        i.sku,
        i.name as product_name,
        SUM(ps.quantity) as total_quantity,
        SUM(ps.quantity * ps.unit_price) as total_revenue
    FROM product_sales ps
    JOIN customer_segments cs ON ps.customer_id = cs.customer_id
    JOIN public.inventory i ON ps.product_id = i.id
    GROUP BY cs.segment, i.sku, i.name
    ORDER BY cs.segment, total_revenue DESC;
END;
$$ LANGUAGE plpgsql;

-- Function for product lifecycle analysis
CREATE OR REPLACE FUNCTION public.get_product_lifecycle_analysis(p_company_id uuid)
RETURNS json AS $$
DECLARE
    result json;
BEGIN
    WITH product_sales_history AS (
        SELECT
            si.product_id,
            date_trunc('month', s.created_at) as sale_month,
            SUM(si.quantity) as monthly_quantity
        FROM public.sale_items si
        JOIN public.sales s ON si.sale_id = s.id
        WHERE s.company_id = p_company_id
        GROUP BY si.product_id, date_trunc('month', s.created_at)
    ),
    product_trends AS (
        SELECT
            product_id,
            (
                SELECT SUM(monthly_quantity)
                FROM product_sales_history psh2
                WHERE psh2.product_id = psh1.product_id AND psh2.sale_month >= (NOW() - interval '90 days')
            ) as sales_last_90,
            (
                SELECT SUM(monthly_quantity)
                FROM product_sales_history psh2
                WHERE psh2.product_id = psh1.product_id AND psh2.sale_month >= (NOW() - interval '180 days') AND psh2.sale_month < (NOW() - interval '90 days')
            ) as sales_prev_90
        FROM product_sales_history psh1
        GROUP BY product_id
    ),
    product_stages AS (
        SELECT
            i.id,
            i.sku,
            i.name,
            (i.quantity * i.cost) as total_revenue,
            CASE
                WHEN i.created_at > (NOW() - interval '60 days') AND i.last_sold_date IS NOT NULL THEN 'Launch'
                WHEN COALESCE(pt.sales_last_90, 0) > COALESCE(pt.sales_prev_90, 0) * 1.5 THEN 'Growth'
                WHEN COALESCE(pt.sales_last_90, 0) < COALESCE(pt.sales_prev_90, 0) * 0.7 THEN 'Decline'
                ELSE 'Maturity'
            END as stage
        FROM public.inventory i
        LEFT JOIN product_trends pt ON i.id = pt.product_id
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL
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
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;


-- Function for cash flow insights
CREATE OR REPLACE FUNCTION public.get_cash_flow_insights(p_company_id uuid)
RETURNS json AS $$
DECLARE
    settings record;
BEGIN
    SELECT * INTO settings FROM public.company_settings WHERE company_id = p_company_id;
    RETURN (
        SELECT json_build_object(
            'dead_stock_value', COALESCE(SUM(i.quantity * i.cost) FILTER (WHERE i.last_sold_date < (CURRENT_DATE - settings.dead_stock_days)), 0),
            'slow_mover_value', COALESCE(SUM(i.quantity * i.cost) FILTER (WHERE i.last_sold_date >= (CURRENT_DATE - settings.dead_stock_days) AND i.last_sold_date < (CURRENT_DATE - 30)), 0),
            'dead_stock_threshold_days', settings.dead_stock_days
        )
        FROM public.inventory i
        WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0
    );
END;
$$ LANGUAGE plpgsql;

-- This adds a missing check constraint on the inventory table
ALTER TABLE public.inventory
ADD CONSTRAINT inventory_quantity_check CHECK (quantity >= 0);

-- Final indexes to improve performance
CREATE INDEX IF NOT EXISTS idx_inventory_company_id_deleted_at ON public.inventory(company_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_sales_company_id_created_at ON public.sales(company_id, created_at);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_product_created ON public.inventory_ledger(company_id, product_id, created_at);
CREATE INDEX IF NOT EXISTS idx_suppliers_company_id ON public.suppliers(company_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);
