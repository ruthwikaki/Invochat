
-- For a new Supabase project, you must run the following queries
-- in the Supabase SQL Editor to set up the database schema.

-- 1. Enable the required "uuid-ossp" extension for UUID generation.
create extension if not exists "uuid-ossp" with schema extensions;

-- 2. Create the "companies" table to hold company-specific information.
create table if not exists public.companies (
  id uuid default extensions.uuid_generate_v4() not null,
  name character varying not null,
  created_at timestamp with time zone not null default now(),
  constraint companies_pkey primary key (id)
);
alter table public.companies enable row level security;

-- 3. Add a "company_id" column to the built-in "users" table.
-- This column will link each user to a specific company.
alter table auth.users
add column if not exists company_id uuid;

-- 4. Create a security policy that allows users to see only their own data.
-- This is a critical security measure in a multi-tenant application.
create policy "Users can see their own data"
on auth.users for select
using ( auth.uid() = id );

-- 5. Create a function to automatically create a new company when a user signs up.
-- This function is triggered by the authentication system.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_name text;
begin
  -- Extract company_name from the user's metadata, falling back to a default.
  company_name := coalesce(new.raw_app_meta_data->>'company_name', 'My Company');

  -- Create a new company for the new user.
  insert into public.companies (name)
  values (company_name)
  returning id into new.company_id;

  -- Update the user's record with the new company_id.
  update auth.users
  set company_id = new.company_id,
      -- Set the user's role to 'Owner' in their app metadata.
      raw_app_meta_data = new.raw_app_meta_data || jsonb_build_object('role', 'Owner')
  where id = new.id;
  
  return new;
end;
$$;

-- 6. Create a trigger that calls the handle_new_user function after a new user is inserted.
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- =================================================================
-- Application Data Tables
-- =================================================================

-- Inventory Table: Core table for all product information.
CREATE TABLE IF NOT EXISTS public.inventory (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID UNIQUE REFERENCES public.products(id) ON DELETE CASCADE,
    quantity INT NOT NULL DEFAULT 0,
    reorder_point INT,
    reorder_quantity INT,
    last_sold_date TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    deleted_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    source_platform VARCHAR(50),
    external_product_id VARCHAR(255),
    external_variant_id VARCHAR(255),
    external_quantity INT
);
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company's inventory" ON public.inventory
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));
CREATE UNIQUE INDEX IF NOT EXISTS inventory_company_platform_variant_idx ON public.inventory(company_id, source_platform, external_variant_id);


-- Products Table: Central repository for product definitions.
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku VARCHAR(100) NOT NULL,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    price INT, -- in cents
    cost INT NOT NULL DEFAULT 0, -- in cents
    barcode VARCHAR(100),
    supplier_id UUID REFERENCES public.suppliers(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company's products" ON public.products
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));
CREATE UNIQUE INDEX IF NOT EXISTS products_company_id_sku_idx ON public.products(company_id, sku);


-- Sales Table: Records every sale transaction.
CREATE TABLE IF NOT EXISTS public.sales (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_number VARCHAR(50) NOT NULL,
    customer_id UUID REFERENCES public.customers(id),
    total_amount INT NOT NULL, -- in cents
    payment_method VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    external_id VARCHAR(255)
);
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company's sales" ON public.sales
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));
CREATE UNIQUE INDEX IF NOT EXISTS sales_company_external_id_idx ON public.sales(company_id, external_id) WHERE external_id IS NOT NULL;


-- Sale Items Table: Line items for each sale.
CREATE TABLE IF NOT EXISTS public.sale_items (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    sale_id UUID NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    quantity INT NOT NULL,
    unit_price INT NOT NULL, -- in cents
    cost_at_time INT -- in cents
);
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company's sale items" ON public.sale_items
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));


-- Suppliers Table: Information about vendors.
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    default_lead_time_days INT,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own suppliers" ON public.suppliers
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));


-- Customers Table: Stores customer information.
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name VARCHAR(255),
    email VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own customers" ON public.customers
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));
CREATE UNIQUE INDEX IF NOT EXISTS customers_company_email_idx ON public.customers(company_id, email) WHERE email IS NOT NULL;


-- Inventory Ledger: An immutable log of all stock movements.
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id),
    change_type VARCHAR(50) NOT NULL, -- e.g., 'sale', 'purchase', 'adjustment'
    quantity_change INT NOT NULL,
    new_quantity INT NOT NULL,
    related_id UUID, -- e.g., sale_id, purchase_order_id
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own inventory ledger" ON public.inventory_ledger
    FOR SELECT USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));


-- Integrations Table: Stores connection details for third-party platforms.
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform VARCHAR(50) NOT NULL,
    shop_domain VARCHAR(255),
    shop_name VARCHAR(255),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ,
    sync_status VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own integrations" ON public.integrations
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));


-- Conversations Table: For storing chat sessions.
CREATE TABLE IF NOT EXISTS public.conversations (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    company_id UUID NOT NULL REFERENCES public.companies(id),
    title VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_accessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_starred BOOLEAN NOT NULL DEFAULT FALSE
);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own conversations" ON public.conversations
    FOR ALL USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());


-- Messages Table: For storing individual chat messages.
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES public.companies(id),
    role VARCHAR(20) NOT NULL,
    content TEXT,
    visualization JSONB,
    confidence REAL,
    assumptions TEXT[],
    component VARCHAR(50),
    component_props JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage messages in their conversations" ON public.messages
    FOR ALL USING (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()))
    WITH CHECK (conversation_id IN (SELECT id FROM public.conversations WHERE user_id = auth.uid()));


-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
    company_id UUID PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
    dead_stock_days INT NOT NULL DEFAULT 90,
    fast_moving_days INT NOT NULL DEFAULT 30,
    overstock_multiplier NUMERIC NOT NULL DEFAULT 3.0,
    high_value_threshold INT NOT NULL DEFAULT 100000, -- in cents
    currency VARCHAR(10) DEFAULT 'USD',
    timezone VARCHAR(50) DEFAULT 'UTC',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own company's settings" ON public.company_settings
    FOR ALL USING (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id))
    WITH CHECK (company_id = (SELECT auth.users.company_id FROM auth.users WHERE auth.uid() = auth.users.id));


-- =================================================================
-- Database Functions
-- =================================================================

-- Function to get distinct categories for a company
CREATE OR REPLACE FUNCTION get_distinct_categories(p_company_id UUID)
RETURNS TABLE(category TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT p.category
    FROM public.products p
    JOIN public.inventory i ON p.id = i.product_id
    WHERE p.company_id = p_company_id AND p.category IS NOT NULL AND i.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to get a unified view of inventory with product and supplier details.
CREATE OR REPLACE FUNCTION get_unified_inventory(
    p_company_id UUID,
    p_query TEXT,
    p_category TEXT,
    p_supplier_id UUID,
    p_product_id_filter UUID,
    p_limit INT,
    p_offset INT
)
RETURNS TABLE (
    product_id UUID,
    sku TEXT,
    product_name TEXT,
    category TEXT,
    quantity INT,
    cost INT,
    price INT,
    total_value BIGINT,
    reorder_point INT,
    supplier_name TEXT,
    supplier_id UUID,
    barcode TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id as product_id,
        p.sku::text,
        p.name::text as product_name,
        p.category::text,
        i.quantity,
        p.cost,
        p.price,
        (i.quantity * p.cost)::bigint as total_value,
        i.reorder_point,
        s.name::text as supplier_name,
        s.id as supplier_id,
        p.barcode::text
    FROM public.products p
    JOIN public.inventory i ON p.id = i.product_id
    LEFT JOIN public.suppliers s ON p.supplier_id = s.id
    WHERE
        p.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND (p_query IS NULL OR (p.name ILIKE '%' || p_query || '%' OR p.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR p.category = p_category)
        AND (p_supplier_id IS NULL OR p.supplier_id = p_supplier_id)
        AND (p_product_id_filter IS NULL OR p.id = p_product_id_filter)
    ORDER BY p.name
    LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;

-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION record_sale_transaction(
    p_company_id UUID,
    p_user_id UUID,
    p_sale_items JSONB[],
    p_customer_name TEXT,
    p_customer_email TEXT,
    p_payment_method TEXT,
    p_notes TEXT,
    p_external_id TEXT
)
RETURNS public.sales AS $$
DECLARE
    new_sale_id UUID;
    new_customer_id UUID;
    total_sale_amount INT := 0;
    item JSONB;
    p_product_id UUID;
    p_quantity INT;
    p_unit_price INT;
    p_cost_at_time INT;
    current_stock INT;
    new_stock INT;
    sale_record public.sales;
BEGIN
    -- Check for existing external ID if provided
    IF p_external_id IS NOT NULL THEN
        SELECT id INTO new_sale_id FROM public.sales WHERE company_id = p_company_id AND external_id = p_external_id;
        IF new_sale_id IS NOT NULL THEN
            -- Sale already exists, return the existing record
            SELECT * INTO sale_record FROM public.sales WHERE id = new_sale_id;
            RETURN sale_record;
        END IF;
    END IF;

    -- Upsert customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email)
        VALUES (p_company_id, p_customer_name, p_customer_email)
        ON CONFLICT (company_id, email) DO UPDATE SET customer_name = EXCLUDED.customer_name
        RETURNING id INTO new_customer_id;
    END IF;

    -- Create sale record
    INSERT INTO public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (p_company_id, 'TEMP', new_customer_id, 0, p_payment_method, p_notes, p_external_id)
    RETURNING id INTO new_sale_id;

    -- Process sale items
    FOREACH item IN ARRAY p_sale_items
    LOOP
        p_product_id := (item->>'product_id')::UUID;
        p_quantity := (item->>'quantity')::INT;
        p_unit_price := (item->>'unit_price')::INT;

        -- Get current cost and stock
        SELECT cost, quantity INTO p_cost_at_time, current_stock
        FROM public.inventory_view WHERE id = p_product_id AND company_id = p_company_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product with ID % not found in inventory', p_product_id;
        END IF;

        -- Insert sale item
        INSERT INTO public.sale_items (sale_id, company_id, product_id, quantity, unit_price, cost_at_time)
        VALUES (new_sale_id, p_company_id, p_product_id, p_quantity, p_unit_price, p_cost_at_time);
        
        total_sale_amount := total_sale_amount + (p_quantity * p_unit_price);

        -- Update inventory quantity and log it
        new_stock := current_stock - p_quantity;
        UPDATE public.inventory SET quantity = new_stock, last_sold_date = NOW() WHERE id = p_product_id;

        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id)
        VALUES (p_company_id, p_product_id, 'sale', -p_quantity, new_stock, new_sale_id);
    END LOOP;

    -- Update sale with total amount and final sale number
    UPDATE public.sales
    SET total_amount = total_sale_amount,
        sale_number = 'SALE-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || (
            SELECT COUNT(*) + 1 FROM public.sales WHERE company_id = p_company_id AND created_at::date = NOW()::date
        )::TEXT
    WHERE id = new_sale_id
    RETURNING * INTO sale_record;

    RETURN sale_record;
END;
$$ LANGUAGE plpgsql;

-- Gets alerts for a company, including low stock, dead stock, and predictive stockouts.
CREATE OR REPLACE FUNCTION public.get_alerts(p_company_id uuid)
RETURNS TABLE(
    type text,
    sku text,
    product_name text,
    product_id uuid,
    current_stock integer,
    reorder_point integer,
    last_sold_date timestamp with time zone,
    value numeric,
    days_of_stock_remaining numeric
)
LANGUAGE plpgsql
AS $$
DECLARE
    settings_row record;
BEGIN
    SELECT * INTO settings_row FROM public.company_settings WHERE company_id = p_company_id;

    IF NOT FOUND THEN
        -- Insert and use default settings if none exist
        INSERT INTO public.company_settings (company_id) VALUES (p_company_id) RETURNING * INTO settings_row;
    END IF;

    RETURN QUERY
    WITH velocity AS (
        SELECT
            p.id as product_id,
            COALESCE(SUM(si.quantity) / NULLIF(settings_row.fast_moving_days, 0)::numeric, 0) as daily_sales_velocity
        FROM public.products p
        JOIN public.sale_items si ON p.id = si.product_id
        JOIN public.sales s ON si.sale_id = s.id
        WHERE p.company_id = p_company_id
          AND s.created_at >= NOW() - (settings_row.fast_moving_days || ' days')::interval
        GROUP BY p.id
    )
    SELECT
        a.alert_type::text,
        a.sku::text,
        a.product_name::text,
        a.product_id,
        a.quantity,
        a.reorder_point,
        a.last_sold_date,
        (a.quantity * a.cost)::numeric / 100 as value,
        CASE
            WHEN v.daily_sales_velocity > 0 THEN a.quantity / v.daily_sales_velocity
            ELSE NULL
        END::numeric AS days_of_stock_remaining
    FROM (
        -- Low Stock Alert
        SELECT
            'low_stock' as alert_type,
            p.sku, p.name as product_name, i.id as product_id, i.quantity, i.reorder_point, i.last_sold_date, p.cost
        FROM public.inventory i
        JOIN public.products p ON i.product_id = p.id
        WHERE i.company_id = p_company_id
          AND i.reorder_point IS NOT NULL
          AND i.quantity < i.reorder_point
          AND i.deleted_at IS NULL

        UNION ALL

        -- Dead Stock Alert
        SELECT
            'dead_stock' as alert_type,
            p.sku, p.name as product_name, i.id as product_id, i.quantity, i.reorder_point, i.last_sold_date, p.cost
        FROM public.inventory i
        JOIN public.products p ON i.product_id = p.id
        WHERE i.company_id = p_company_id
          AND i.last_sold_date IS NOT NULL
          AND i.last_sold_date < NOW() - (settings_row.dead_stock_days || ' days')::interval
          AND i.quantity > 0
          AND i.deleted_at IS NULL
          
        UNION ALL
        
        -- Predictive Stockout Alert
        SELECT
            'predictive' as alert_type,
            p.sku, p.name as product_name, i.id as product_id, i.quantity, i.reorder_point, i.last_sold_date, p.cost
        FROM public.inventory i
        JOIN public.products p ON i.product_id = p.id
        JOIN velocity v_inner ON p.id = v_inner.product_id
        WHERE i.company_id = p_company_id
          AND v_inner.daily_sales_velocity > 0
          AND (i.quantity / v_inner.daily_sales_velocity) < COALESCE(p_settings.predictive_stock_days, 7)
          AND i.deleted_at IS NULL
          AND (i.reorder_point IS NULL OR i.quantity >= i.reorder_point) -- Only trigger if not already low stock
    ) AS a
    LEFT JOIN velocity v ON a.product_id = v.product_id
    LEFT JOIN company_settings p_settings ON a.company_id = p_settings.company_id;
END;
$$;


-- Function to get a summary of schema and data for display.
CREATE OR REPLACE FUNCTION get_schema_and_data(p_company_id UUID)
RETURNS TABLE (table_name TEXT, rows JSONB) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.table_name,
        (SELECT jsonb_agg(row_to_json(tbl)) FROM (SELECT * FROM public.products WHERE company_id = p_company_id LIMIT 5) tbl) as rows
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' AND t.table_name = 'products'
    UNION ALL
    SELECT
        t.table_name,
        (SELECT jsonb_agg(row_to_json(tbl)) FROM (SELECT * FROM public.inventory WHERE company_id = p_company_id AND deleted_at IS NULL LIMIT 5) tbl) as rows
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' AND t.table_name = 'inventory'
    UNION ALL
     SELECT
        t.table_name,
        (SELECT jsonb_agg(row_to_json(tbl)) FROM (SELECT * FROM public.sales WHERE company_id = p_company_id LIMIT 5) tbl) as rows
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' AND t.table_name = 'sales'
     UNION ALL
     SELECT
        t.table_name,
        (SELECT jsonb_agg(row_to_json(tbl)) FROM (SELECT * FROM public.customers WHERE company_id = p_company_id AND deleted_at IS NULL LIMIT 5) tbl) as rows
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' AND t.table_name = 'customers';
END;
$$ LANGUAGE plpgsql;


-- Function to get cash flow insights
CREATE OR REPLACE FUNCTION get_cash_flow_insights(p_company_id UUID)
RETURNS TABLE (
    dead_stock_value NUMERIC,
    slow_mover_value NUMERIC,
    dead_stock_threshold_days INT
) AS $$
DECLARE
    settings_row record;
BEGIN
    SELECT * INTO settings_row FROM public.company_settings WHERE company_id = p_company_id;
    
    IF NOT FOUND THEN
        INSERT INTO public.company_settings (company_id) VALUES (p_company_id) RETURNING * INTO settings_row;
    END IF;

    RETURN QUERY
    SELECT
        COALESCE(SUM(CASE WHEN i.last_sold_date < NOW() - (settings_row.dead_stock_days || ' days')::interval THEN (i.quantity * p.cost) / 100.0 ELSE 0 END), 0) AS dead_stock_value,
        COALESCE(SUM(CASE WHEN i.last_sold_date >= NOW() - (settings_row.dead_stock_days || ' days')::interval AND i.last_sold_date < NOW() - '30 days'::interval THEN (i.quantity * p.cost) / 100.0 ELSE 0 END), 0) AS slow_mover_value,
        settings_row.dead_stock_days
    FROM public.inventory i
    JOIN public.products p ON i.product_id = p.id
    WHERE i.company_id = p_company_id AND i.deleted_at IS NULL AND i.quantity > 0;
END;
$$ LANGUAGE plpgsql;

-- Final setup: Grant usage rights to Supabase's authenticated role.
grant usage on schema public to anon, authenticated;
grant all privileges on all tables in schema public to anon, authenticated;
grant all privileges on all functions in schema public to anon, authenticated;
grant all privileges on all sequences in schema public to anon, authenticated;

alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on functions to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
