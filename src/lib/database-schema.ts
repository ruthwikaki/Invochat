
-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

-- ========= Part 1: Custom Types =========

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE public.po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled');
    END IF;
END$$;


-- ========= Part 2: Core Table Definitions =========
-- All tables are created with IF NOT EXISTS for idempotency

CREATE TABLE IF NOT EXISTS public.companies (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  name character varying NOT NULL,
  subscription_status character varying DEFAULT 'active'::character varying,
  subscription_tier character varying DEFAULT 'basic'::character varying,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT companies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.users (
  id uuid NOT NULL,
  company_id uuid,
  email character varying NOT NULL,
  full_name character varying,
  role character varying DEFAULT 'user'::character varying CHECK (role::text = ANY (ARRAY['Owner'::character varying, 'Admin'::character varying, 'Member'::character varying]::text[])),
  last_login timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  deleted_at timestamp with time zone,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
  CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);


CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid NOT NULL,
  dead_stock_days integer NOT NULL DEFAULT 90,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold numeric NOT NULL DEFAULT 1000,
  fast_moving_days integer NOT NULL DEFAULT 30,
  custom_rules jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  currency text DEFAULT 'USD'::text,
  timezone text DEFAULT 'UTC'::text,
  tax_rate numeric DEFAULT 0,
  predictive_stock_days integer DEFAULT 7,
  theme_primary_color text DEFAULT '256 75% 61%'::text,
  theme_background_color text DEFAULT '222 83% 4%'::text,
  theme_accent_color text DEFAULT '217 33% 17%'::text,
  CONSTRAINT company_settings_pkey PRIMARY KEY (company_id),
  CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);


CREATE TABLE IF NOT EXISTS public.locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  name text NOT NULL,
  address text,
  is_default boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT locations_pkey PRIMARY KEY (id),
  CONSTRAINT locations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);

CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  sku character varying NOT NULL,
  name character varying NOT NULL,
  description text,
  quantity integer DEFAULT 0 CHECK (quantity >= 0),
  cost numeric DEFAULT 0 CHECK (cost >= 0::numeric),
  price numeric DEFAULT 0 CHECK (price >= 0::numeric),
  reorder_point integer DEFAULT 0,
  supplier_name character varying,
  category character varying,
  last_sold_date date,
  on_order_quantity integer NOT NULL DEFAULT 0,
  landed_cost numeric,
  location_id uuid,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamp with time zone DEFAULT now(),
  source_platform text,
  external_product_id text,
  external_variant_id text,
  external_quantity integer,
  last_sync timestamp with time zone,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  barcode character varying,
  CONSTRAINT inventory_pkey PRIMARY KEY (id),
  CONSTRAINT inventory_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT fk_inventory_location FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL,
  CONSTRAINT inventory_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.users(id),
  CONSTRAINT inventory_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.vendors (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  vendor_name character varying,
  address text,
  contact_info character varying,
  terms character varying,
  account_number character varying,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT vendors_pkey PRIMARY KEY (id),
  CONSTRAINT vendors_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id)
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  po_number character varying,
  order_date date,
  expected_date date,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  supplier_id uuid,
  status public.po_status,
  total_amount numeric,
  notes text,
  CONSTRAINT purchase_orders_pkey PRIMARY KEY (id),
  CONSTRAINT purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id),
  CONSTRAINT purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.vendors(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  po_id uuid NOT NULL,
  sku text NOT NULL,
  quantity_ordered integer NOT NULL CHECK (quantity_ordered > 0),
  quantity_received integer NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost numeric NOT NULL,
  tax_rate numeric NOT NULL DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT purchase_order_items_pkey PRIMARY KEY (id),
  CONSTRAINT purchase_order_items_po_id_fkey FOREIGN KEY (po_id) REFERENCES public.purchase_orders(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.customers (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  customer_name character varying,
  email character varying,
  platform text,
  external_id text,
  deleted_at timestamp with time zone,
  status text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT customers_pkey PRIMARY KEY (id),
  CONSTRAINT customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL,
  sale_date timestamp with time zone NOT NULL DEFAULT now(),
  total_amount numeric DEFAULT 0,
  platform character varying,
  external_id text,
  customer_id uuid,
  sales_channel text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT sales_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL,
  CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE SET NULL
);


CREATE TABLE IF NOT EXISTS public.order_items (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  sale_id uuid NOT NULL,
  sku character varying,
  quantity integer NOT NULL,
  unit_price numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT order_items_pkey PRIMARY KEY (id),
  CONSTRAINT sale_items_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES public.orders(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT true,
  last_sync_at timestamp with time zone,
  sync_status text,
  access_token text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT integrations_pkey PRIMARY KEY (id),
  CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

-- Chat & AI Tables
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  company_id uuid NOT NULL,
  title text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  last_accessed_at timestamp with time zone DEFAULT now(),
  is_starred boolean DEFAULT false,
  CONSTRAINT conversations_pkey PRIMARY KEY (id),
  CONSTRAINT conversations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE,
  CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL,
  company_id uuid NOT NULL,
  role text NOT NULL CHECK (role = ANY (ARRAY['user'::text, 'assistant'::text, 'tool'::text])),
  content text NOT NULL,
  visualization jsonb,
  confidence numeric,
  assumptions text[],
  component TEXT,
  component_props JSONB,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT messages_pkey PRIMARY KEY (id),
  CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE
);

-- Logging and Utility Tables
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  sku text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  change_type text NOT NULL,
  quantity_change integer NOT NULL,
  new_quantity integer NOT NULL,
  related_id uuid,
  notes text,
  CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id),
  CONSTRAINT inventory_ledger_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.company_dashboard_metrics (
    company_id UUID PRIMARY KEY,
    total_skus BIGINT,
    inventory_value NUMERIC,
    low_stock_count BIGINT,
    last_refreshed TIMESTAMPTZ
);
-- ========= Part 3: Schema Migrations & Constraints =========

-- Add all unique constraints (wrapped for idempotency)
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_sku_per_company') THEN ALTER TABLE public.inventory ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_variant_per_company') THEN ALTER TABLE public.inventory ADD CONSTRAINT unique_variant_per_company UNIQUE (company_id, source_platform, external_variant_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_location_name_per_company') THEN ALTER TABLE public.locations ADD CONSTRAINT unique_location_name_per_company UNIQUE (company_id, name); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_vendor_name_per_company') THEN ALTER TABLE public.vendors ADD CONSTRAINT unique_vendor_name_per_company UNIQUE (vendor_name, company_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_customer_per_platform') THEN ALTER TABLE public.customers ADD CONSTRAINT unique_customer_per_platform UNIQUE (company_id, platform, external_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_order_per_platform') THEN ALTER TABLE public.orders ADD CONSTRAINT unique_order_per_platform UNIQUE (company_id, platform, external_id); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_po_number_per_company') THEN ALTER TABLE public.purchase_orders ADD CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number); END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_platform_per_company') THEN ALTER TABLE public.integrations ADD CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform); END IF; END $$;

-- ========= Part 4: Functions & Triggers =========

-- Function to handle new user creation with proper metadata handling
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    new_company_id UUID;
    user_role TEXT := 'Owner';
    new_company_name TEXT;
BEGIN
    RAISE NOTICE '[handle_new_user] Trigger started for user %', new.email;

    -- Check for Supabase environment
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        RAISE WARNING '[handle_new_user] Auth schema not found. Skipping trigger logic.';
        RETURN new;
    END IF;

    -- Handle invited users vs. new sign-ups
    IF new.invited_at IS NOT NULL THEN
        RAISE NOTICE '[handle_new_user] Processing invited user.';
        user_role := 'Member';
        -- **FIX**: Use raw_user_meta_data for invites, which is set by supabase.auth.admin.inviteUserByEmail
        new_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
        IF new_company_id IS NULL THEN
            RAISE EXCEPTION 'Invited user sign-up failed: company_id was missing from user metadata.';
        END IF;
    ELSE
        RAISE NOTICE '[handle_new_user] Processing new direct sign-up.';
        user_role := 'Owner';
        -- **FIX**: Use raw_app_meta_data for client-side signups
        new_company_name := COALESCE(new.raw_app_meta_data->>'company_name', new.email || '''s Company');
        
        -- Create the new company record
        BEGIN
            RAISE NOTICE '[handle_new_user] Attempting to insert into public.companies with name: %', new_company_name;
            INSERT INTO public.companies (name) VALUES (new_company_name) RETURNING id INTO new_company_id;
            RAISE NOTICE '[handle_new_user] Successfully created company with ID: %', new_company_id;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION 'Failed to insert into public.companies: %', SQLERRM;
        END;
    END IF;

    -- Insert into our public users table, which links auth.users to our application data.
    BEGIN
        RAISE NOTICE '[handle_new_user] Attempting to insert into public.users with user_id: %, company_id: %', new.id, new_company_id;
        INSERT INTO public.users (id, company_id, email, role)
        VALUES (new.id, new_company_id, new.email, user_role);
        RAISE NOTICE '[handle_new_user] Successfully inserted into public.users.';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Failed to insert into public.users: %', SQLERRM;
    END;

    -- For new Owners, create default settings entry.
    IF user_role = 'Owner' THEN
        BEGIN
            RAISE NOTICE '[handle_new_user] Attempting to insert default settings for company_id: %', new_company_id;
            INSERT INTO public.company_settings (company_id) VALUES (new_company_id) ON CONFLICT (company_id) DO NOTHING;
            RAISE NOTICE '[handle_new_user] Successfully inserted into company_settings.';
        EXCEPTION
            WHEN OTHERS THEN
                RAISE EXCEPTION 'Failed to insert into public.company_settings: %', SQLERRM;
        END;
    END IF;
    
    -- Update the app_metadata in auth.users to store company_id and role.
    -- This makes it available in the JWT for RLS policies.
    BEGIN
        RAISE NOTICE '[handle_new_user] Attempting to update auth.users metadata for user_id: %', new.id;
        UPDATE auth.users
        SET app_metadata = COALESCE(app_metadata, '{}'::jsonb) || jsonb_build_object('role', user_role, 'company_id', new_company_id)
        WHERE id = new.id;
        RAISE NOTICE '[handle_new_user] Successfully updated auth.users metadata.';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Failed to update auth.users metadata: %', SQLERRM;
    END;

    RAISE NOTICE '[handle_new_user] Trigger finished successfully.';
    RETURN new;
END;
$$;


-- Create auth user trigger only in Supabase environments
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'auth') THEN
        DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
        CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
    END IF;
END $$;

-- Batch upsert function
CREATE OR REPLACE FUNCTION public.batch_upsert_with_transaction(
    p_table_name text, p_records jsonb, p_conflict_columns text[]
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    company_id_from_jwt uuid;
    sanitized_records jsonb;
    update_set_clause text;
    query text;
BEGIN
    BEGIN
        company_id_from_jwt := (auth.jwt() -> 'app_metadata' ->> 'company_id')::uuid;
    EXCEPTION
        WHEN OTHERS THEN
            company_id_from_jwt := NULL;
    END;

    IF p_table_name NOT IN ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers') THEN
        RAISE EXCEPTION 'Invalid table for batch upsert: %', p_table_name;
    END IF;
    
    IF company_id_from_jwt IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_set(elem, '{company_id}', to_jsonb(company_id_from_jwt))) INTO sanitized_records FROM jsonb_array_elements(p_records) AS elem;
    ELSE
        sanitized_records := p_records;
    END IF;
    
    update_set_clause := (SELECT string_agg(format('%I = excluded.%I', key, key), ', ') FROM jsonb_object_keys(sanitized_records -> 0) AS key WHERE NOT (key = ANY(p_conflict_columns)));
    query := format('INSERT INTO %I SELECT * FROM jsonb_populate_recordset(null::%I, $1) ON CONFLICT (%s) DO UPDATE SET %s, updated_at = NOW();', p_table_name, p_table_name, array_to_string(p_conflict_columns, ', '), update_set_clause);
    EXECUTE query USING sanitized_records;
END;
$$;

-- Dashboard metrics refresh function
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics_for_company(p_company_id uuid)
RETURNS VOID AS $$
BEGIN
    DELETE FROM company_dashboard_metrics WHERE company_id = p_company_id;
    INSERT INTO company_dashboard_metrics (company_id, total_skus, inventory_value, low_stock_count, last_refreshed)
    SELECT p_company_id, COUNT(DISTINCT i.sku), SUM(i.quantity * i.cost), COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END), NOW()
    FROM inventory i WHERE i.company_id = p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ========= Part 5: RPC Functions =========
CREATE OR REPLACE FUNCTION public.get_dashboard_metrics(p_company_id uuid, p_days integer)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
    start_date timestamptz := now() - (p_days || ' days')::interval;
BEGIN
    WITH date_series AS (
        SELECT generate_series(start_date::date, now()::date, '1 day'::interval) as date
    ),
    sales_data AS (
        SELECT
            date_trunc('day', o.sale_date)::date as sale_day,
            SUM(oi.quantity * oi.unit_price) as daily_revenue,
            SUM(oi.quantity * (oi.unit_price - COALESCE(i.cost, 0))) as daily_profit,
            COUNT(DISTINCT o.id) as daily_orders
        FROM orders o
        JOIN order_items oi ON o.id = oi.sale_id
        LEFT JOIN inventory i ON oi.sku = i.sku AND o.company_id = i.company_id
        WHERE o.company_id = p_company_id AND o.sale_date >= start_date
        GROUP BY 1
    ),
    totals AS (
        SELECT 
            COALESCE(SUM(daily_revenue), 0) as total_revenue,
            COALESCE(SUM(daily_profit), 0) as total_profit,
            COALESCE(SUM(daily_orders), 0) as total_orders
        FROM sales_data
    )
    SELECT json_build_object(
        'totalSalesValue', (SELECT total_revenue FROM totals),
        'totalProfit', (SELECT total_profit FROM totals),
        'totalOrders', (SELECT total_orders FROM totals),
        'averageOrderValue', (SELECT CASE WHEN total_orders > 0 THEN total_revenue / total_orders ELSE 0 END FROM totals),
        'deadStockItemsCount', (SELECT COUNT(*) FROM inventory WHERE company_id = p_company_id AND last_sold_date < now() - '90 days'::interval AND deleted_at IS NULL),
        'salesTrendData', (
            SELECT json_agg(json_build_object('date', ds.date, 'Sales', COALESCE(sd.daily_revenue, 0)))
            FROM date_series ds
            LEFT JOIN sales_data sd ON ds.date = sd.sale_day
        ),
        'inventoryByCategoryData', (
            SELECT json_agg(json_build_object('name', COALESCE(category, 'Uncategorized'), 'value', category_value))
            FROM (
                SELECT category, SUM(quantity * cost) as category_value
                FROM inventory
                WHERE company_id = p_company_id AND deleted_at IS NULL
                GROUP BY category
                ORDER BY category_value DESC
                LIMIT 5
            ) cat_data
        ),
        'topCustomersData', (
            SELECT json_agg(json_build_object('name', customer_name, 'value', customer_total))
            FROM (
                SELECT c.customer_name, SUM(o.total_amount) as customer_total
                FROM orders o
                JOIN customers c ON o.customer_id = c.id
                WHERE o.company_id = p_company_id 
                    AND o.sale_date >= start_date 
                    AND c.deleted_at IS NULL
                GROUP BY c.customer_name
                ORDER BY customer_total DESC
                LIMIT 5
            ) cust_data
        )
    ) INTO result_json;

    RETURN result_json;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_purchase_order_details(p_po_id uuid, p_company_id uuid)
RETURNS TABLE(id uuid, company_id uuid, supplier_id uuid, po_number text, status po_status, order_date text, expected_date text, total_amount numeric, notes text, created_at text, updated_at text, supplier_name text, supplier_email text, items json)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        po.id,
        po.company_id,
        po.supplier_id,
        po.po_number,
        po.status,
        po.order_date::text,
        po.expected_date::text,
        po.total_amount,
        po.notes,
        po.created_at::text,
        po.updated_at::text,
        v.vendor_name,
        v.contact_info as supplier_email,
        (SELECT json_agg(
            json_build_object(
                'id', poi.id,
                'po_id', poi.po_id,
                'sku', poi.sku,
                'product_name', i.name,
                'quantity_ordered', poi.quantity_ordered,
                'quantity_received', poi.quantity_received,
                'unit_cost', poi.unit_cost,
                'tax_rate', poi.tax_rate
            )
        )
        FROM purchase_order_items poi
        LEFT JOIN inventory i ON poi.sku = i.sku AND i.company_id = p_company_id
        WHERE poi.po_id = po.id) as items
    FROM public.purchase_orders po
    LEFT JOIN public.vendors v ON po.supplier_id = v.id
    WHERE po.id = p_po_id AND po.company_id = p_company_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.get_customers_with_stats(
    p_company_id uuid,
    p_query text,
    p_limit integer,
    p_offset integer
)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH customer_stats AS (
        SELECT
            c.id,
            c.company_id,
            c.platform,
            c.external_id,
            c.customer_name,
            c.email,
            c.status,
            c.deleted_at,
            c.created_at,
            COUNT(o.id) as total_orders,
            COALESCE(SUM(o.total_amount), 0) as total_spend
        FROM public.customers c
        LEFT JOIN public.orders o ON c.id = o.customer_id
        WHERE c.company_id = p_company_id
          AND c.deleted_at IS NULL
          AND (
            p_query IS NULL OR
            c.customer_name ILIKE '%' || p_query || '%' OR
            c.email ILIKE '%' || p_query || '%'
          )
        GROUP BY c.id
    ),
    count_query AS (
        SELECT count(*) as total FROM customer_stats
    )
    SELECT json_build_object(
        'items', (SELECT json_agg(cs) FROM (
            SELECT * FROM customer_stats ORDER BY total_spend DESC LIMIT p_limit OFFSET p_offset
        ) cs),
        'totalCount', (SELECT total FROM count_query)
    ) INTO result_json;
    
    RETURN result_json;
END;
$$;


-- ========= Part 6: Row-Level Security (RLS) Policies =========

-- RLS helper functions (safe for non-Supabase environments)
CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT CASE 
        WHEN EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'jwt' AND pronamespace = 'auth'::regnamespace) THEN
            (auth.jwt()->'app_metadata'->>'company_id')::uuid
        ELSE
            NULL::uuid
    END;
$$;

-- Enable RLS and create policies only if auth functions exist
DO $$
DECLARE
    t_name TEXT;
    has_auth BOOLEAN;
BEGIN
    -- Check if auth.jwt() exists
    SELECT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'jwt' AND pronamespace = 'auth'::regnamespace) INTO has_auth;
    
    IF has_auth THEN
        -- Enable RLS on all tables with a direct company_id
        FOR t_name IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN (
            'users', 'company_settings', 'inventory', 'customers', 'orders', 'vendors', 
            'purchase_orders', 'integrations', 'locations', 'inventory_ledger', 'conversations', 'messages'
        ) LOOP
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t_name);
            EXECUTE format('DROP POLICY IF EXISTS "Enable all access for own company" ON public.%I;', t_name);
            EXECUTE format('CREATE POLICY "Enable all access for own company" ON public.%I FOR ALL USING (company_id = public.current_user_company_id()) WITH CHECK (company_id = public.current_user_company_id());', t_name);
        END LOOP;

        ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.order_items;
        CREATE POLICY "Enable all access for own company" ON public.order_items FOR ALL
            USING ((SELECT company_id FROM public.orders WHERE id = sale_id) = public.current_user_company_id());

        ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Enable all access for own company" ON public.purchase_order_items;
        CREATE POLICY "Enable all access for own company" ON public.purchase_order_items FOR ALL
            USING ((SELECT company_id FROM public.purchase_orders WHERE id = po_id) = public.current_user_company_id());
            
        ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Users can see their own company" ON public.companies;
        CREATE POLICY "Users can see their own company" ON public.companies FOR SELECT
            USING (id = public.current_user_company_id());
    ELSE
        RAISE NOTICE 'Auth functions not found - skipping RLS policies';
    END IF;
END $$;
-- ========= Script Completion =========
DO $$
BEGIN
    RAISE NOTICE 'InvoChat database setup completed successfully!';
END $$;


