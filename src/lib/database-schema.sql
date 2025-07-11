
-- InvoChat: From-Scratch Simplified Schema for Inventory Intelligence
-- Version 2.0
-- This script SETS UP a NEW, FOCUSED database. It is destructive and not a migration.
-- RUN THIS ON A CLEAN DATABASE or after dropping all old InvoChat tables.

--== EXTENSIONS ==--
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--== TYPES ==--
-- Define a user role type
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE public.user_role AS ENUM ('Owner', 'Admin', 'Member');
    END IF;
END$$;


--== TABLES ==--

-- Companies Table: Core tenant information
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.companies IS 'Stores company information, acting as the primary tenant for data isolation.';

-- Users Table: Stores app-specific user data, linked to auth.users
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email text,
  role user_role NOT NULL DEFAULT 'Member',
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.users IS 'Stores application-specific user data, including their role and company affiliation.';

-- Company Settings Table
CREATE TABLE IF NOT EXISTS public.company_settings (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  dead_stock_days integer NOT NULL DEFAULT 90,
  overstock_multiplier numeric NOT NULL DEFAULT 3,
  high_value_threshold numeric NOT NULL DEFAULT 100000, -- Stored in cents
  fast_moving_days integer NOT NULL DEFAULT 30,
  predictive_stock_days integer NOT NULL DEFAULT 7,
  currency text DEFAULT 'USD',
  timezone text DEFAULT 'UTC',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);
COMMENT ON TABLE public.company_settings IS 'Stores business rule thresholds and general settings for a company.';

-- Suppliers Table (Simplified)
CREATE TABLE IF NOT EXISTS public.suppliers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text,
  phone text,
  default_lead_time_days integer,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.suppliers IS 'Stores basic supplier contact and lead time information.';

-- Inventory Table (Simplified)
CREATE TABLE IF NOT EXISTS public.inventory (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku text NOT NULL,
  name text NOT NULL,
  category text,
  quantity integer NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  cost integer NOT NULL DEFAULT 0, -- Stored in cents
  price integer, -- Stored in cents
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
  supplier_id uuid REFERENCES public.suppliers(id) ON DELETE SET NULL
);
COMMENT ON TABLE public.inventory IS 'The core table for tracking product inventory levels and costs.';
-- Drop and recreate unique constraint to ensure idempotency
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS inventory_company_id_sku_key;
ALTER TABLE public.inventory ADD CONSTRAINT inventory_company_id_sku_key UNIQUE (company_id, sku);


-- Inventory Ledger Table (New)
CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL,
    change_type text NOT NULL, -- e.g., 'sale', 'restock', 'adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    related_id uuid, -- e.g., sale_id for a sale, or null for manual adjustment
    notes text
);
COMMENT ON TABLE public.inventory_ledger IS 'Append-only log of all inventory changes for audit purposes.';
-- Drop and recreate foreign key constraint to ensure idempotency
ALTER TABLE public.inventory_ledger DROP CONSTRAINT IF EXISTS inventory_ledger_product_id_fkey;
ALTER TABLE public.inventory_ledger ADD CONSTRAINT inventory_ledger_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE CASCADE;


-- Customers Table
CREATE TABLE IF NOT EXISTS public.customers (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  customer_name text NOT NULL,
  email text,
  total_orders integer DEFAULT 0,
  total_spent integer DEFAULT 0, -- Stored in cents
  first_order_date date,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now()
);
COMMENT ON TABLE public.customers IS 'Stores customer information aggregated from sales.';

-- Sales Table
CREATE TABLE IF NOT EXISTS public.sales (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sale_number text NOT NULL,
  customer_id uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  total_amount integer NOT NULL, -- Stored in cents
  payment_method text,
  notes text,
  created_at timestamptz DEFAULT now(),
  external_id text
);
COMMENT ON TABLE public.sales IS 'Records sales transactions.';
-- Drop and recreate unique constraint to ensure idempotency
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_company_id_sale_number_key;
ALTER TABLE public.sales ADD CONSTRAINT sales_company_id_sale_number_key UNIQUE (company_id, sale_number);


-- Sale Items Table
CREATE TABLE IF NOT EXISTS public.sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES public.sales(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    product_id uuid NOT NULL, -- Changed from sku to product_id
    product_name text,
    quantity integer NOT NULL,
    unit_price integer NOT NULL, -- Stored in cents
    cost_at_time integer -- Stored in cents
);
COMMENT ON TABLE public.sale_items IS 'Stores individual line items for each sale.';
-- Drop and recreate foreign key constraint to ensure idempotency
ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS sale_items_product_id_fkey;
ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.inventory(id) ON DELETE RESTRICT;

-- Conversations, Messages, Integrations, etc. (Supporting Tables)
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  title text NOT NULL,
  created_at timestamptz DEFAULT now(),
  last_accessed_at timestamptz DEFAULT now(),
  is_starred boolean DEFAULT false
);

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

CREATE TABLE IF NOT EXISTS public.integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

--== FUNCTIONS ==--

-- Function to handle new user setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  new_company_id uuid;
BEGIN
  -- Create a new company for the new user
  INSERT INTO public.companies (name)
  VALUES (new.raw_user_meta_data->>'company_name')
  RETURNING id INTO new_company_id;

  -- Create a corresponding entry in the public.users table
  INSERT INTO public.users (id, company_id, email, role)
  VALUES (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata with the new company_id and role
  UPDATE auth.users
  SET app_metadata = jsonb_set(
      jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(new_company_id)),
      '{role}', to_jsonb('Owner'::text)
  )
  WHERE id = new.id;
  
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Function to record a sale and update inventory atomically
CREATE OR REPLACE FUNCTION public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid, -- can be null for system-generated sales
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS sales AS $$
DECLARE
    new_sale sales;
    new_customer_id uuid;
    item record;
    inv_record record;
    total_sale_amount integer := 0;
    sale_item_data jsonb;
    new_sale_items sale_items[] := ARRAY[]::sale_items[];
BEGIN
    -- 1. Upsert Customer
    IF p_customer_email IS NOT NULL THEN
        INSERT INTO public.customers (company_id, customer_name, email, first_order_date, total_orders, total_spent)
        VALUES (p_company_id, COALESCE(p_customer_name, p_customer_email), p_customer_email, now(), 1, 0)
        ON CONFLICT (company_id, email) DO UPDATE
        SET
            total_orders = customers.total_orders + 1,
            customer_name = COALESCE(p_customer_name, customers.customer_name)
        RETURNING id INTO new_customer_id;
    END IF;

    -- 2. Create Sale Record
    INSERT INTO public.sales (company_id, sale_number, customer_id, total_amount, payment_method, notes, external_id)
    VALUES (
        p_company_id,
        'SALE-' || (SELECT to_hex(nextval('serial'))),
        new_customer_id,
        0, -- Placeholder, will be updated later
        p_payment_method,
        p_notes,
        p_external_id
    ) RETURNING * INTO new_sale;

    -- 3. Process sale items
    FOR item IN SELECT * FROM jsonb_to_recordset(p_sale_items) AS x(sku text, quantity integer, unit_price integer, product_name text)
    LOOP
        -- Find inventory item by SKU
        SELECT * INTO inv_record FROM public.inventory WHERE sku = item.sku AND company_id = p_company_id AND deleted_at IS NULL;

        IF inv_record IS NULL THEN
            RAISE EXCEPTION 'Product with SKU % not found.', item.sku;
        END IF;

        IF inv_record.quantity < item.quantity THEN
            RAISE EXCEPTION 'Not enough stock for SKU %. Available: %, Requested: %', item.sku, inv_record.quantity, item.quantity;
        END IF;

        -- Update inventory quantity and last sold date
        UPDATE public.inventory
        SET
            quantity = quantity - item.quantity,
            last_sold_date = now()
        WHERE id = inv_record.id;

        -- Create sale item record
        INSERT INTO public.sale_items (sale_id, company_id, product_id, product_name, quantity, unit_price, cost_at_time)
        VALUES (new_sale.id, p_company_id, inv_record.id, COALESCE(item.product_name, inv_record.name), item.quantity, item.unit_price, inv_record.cost)
        RETURNING * INTO sale_item_data;

        -- Log the change in the inventory ledger
        INSERT INTO public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
        VALUES (p_company_id, inv_record.id, 'sale', -item.quantity, inv_record.quantity - item.quantity, new_sale.id, 'Sale #' || new_sale.sale_number);

        -- Accumulate total amount
        total_sale_amount := total_sale_amount + (item.quantity * item.unit_price);
    END LOOP;

    -- 4. Update the final total amount in the sales record
    UPDATE public.sales SET total_amount = total_sale_amount WHERE id = new_sale.id;
    
    -- 5. Update customer's total spent
    IF new_customer_id IS NOT NULL THEN
        UPDATE public.customers SET total_spent = customers.total_spent + total_sale_amount WHERE id = new_customer_id;
    END IF;

    RETURN new_sale;
END;
$$ LANGUAGE plpgsql;


-- Function to get reorder suggestions
CREATE OR REPLACE FUNCTION public.get_reorder_suggestions(p_company_id uuid)
RETURNS TABLE(
    product_id uuid,
    sku text,
    product_name text,
    current_quantity integer,
    reorder_point integer,
    suggested_reorder_quantity integer,
    supplier_name text,
    supplier_id uuid,
    unit_cost integer
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        i.id as product_id,
        i.sku,
        i.name as product_name,
        i.quantity as current_quantity,
        i.reorder_point,
        (i.reorder_point - i.quantity) as suggested_reorder_quantity,
        s.name as supplier_name,
        s.id as supplier_id,
        i.cost as unit_cost
    FROM
        public.inventory i
    LEFT JOIN
        public.suppliers s ON i.supplier_id = s.id
    WHERE
        i.company_id = p_company_id
        AND i.deleted_at IS NULL
        AND i.quantity < i.reorder_point;
END;
$$ LANGUAGE plpgsql;

-- Function to get unified inventory view
CREATE OR REPLACE FUNCTION public.get_unified_inventory(
    p_company_id uuid,
    p_query text DEFAULT NULL,
    p_category text DEFAULT NULL,
    p_supplier_id uuid DEFAULT NULL,
    p_product_id_filter uuid DEFAULT NULL,
    p_limit integer DEFAULT 50,
    p_offset integer DEFAULT 0
)
RETURNS TABLE(items json, total_count bigint) AS $$
DECLARE
    query_sql text;
    count_sql text;
    where_clauses text[] := ARRAY['i.company_id = $1', 'i.deleted_at IS NULL'];
BEGIN
    IF p_query IS NOT NULL AND p_query != '' THEN
        where_clauses := array_append(where_clauses, '(i.name ILIKE $2 OR i.sku ILIKE $2)');
    END IF;
    IF p_category IS NOT NULL AND p_category != '' AND p_category != 'all' THEN
        where_clauses := array_append(where_clauses, 'i.category = $3');
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        where_clauses := array_append(where_clauses, 'i.supplier_id = $4');
    END IF;
    IF p_product_id_filter IS NOT NULL THEN
        where_clauses := array_append(where_clauses, 'i.id = $5');
    END IF;

    query_sql := 'SELECT json_agg(t) FROM (SELECT i.id as product_id, i.sku, i.name as product_name, i.category, i.quantity, i.cost, i.price, (i.quantity * i.cost) as total_value, i.reorder_point, s.name as supplier_name, s.id as supplier_id FROM public.inventory i LEFT JOIN public.suppliers s ON i.supplier_id = s.id WHERE '
                 || array_to_string(where_clauses, ' AND ')
                 || ' ORDER BY i.name LIMIT $6 OFFSET $7) t';

    count_sql := 'SELECT count(*) FROM public.inventory i WHERE ' || array_to_string(where_clauses, ' AND ');

    EXECUTE 'SELECT (' || query_sql || '), (' || count_sql || ')'
    INTO items, total_count
    USING p_company_id, '%' || p_query || '%', p_category, p_supplier_id, p_product_id_filter, p_limit, p_offset;
END;
$$ LANGUAGE plpgsql;


--== INDEXES ==--
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku ON public.inventory(company_id, sku);
CREATE INDEX IF NOT EXISTS idx_inventory_category ON public.inventory(company_id, category);
CREATE INDEX IF NOT EXISTS idx_sales_company_id ON public.sales(company_id);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_product_id ON public.inventory_ledger(product_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_name_company ON public.suppliers(company_id, name);

--== VIEWS (Materialized) ==--
-- Materialized views for performance-intensive dashboard queries can be created here.
-- Example:
-- CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS ...
-- Remember to refresh them after data changes.

--== SECURITY ==--
-- Enable Row Level Security (RLS) on all tables
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;

-- Policies: Users can only see data for their own company
DROP POLICY IF EXISTS "Users can read own company data" ON public.companies;
CREATE POLICY "Users can read own company data" ON public.companies FOR SELECT USING (id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own user record" ON public.users;
CREATE POLICY "Users can manage their own user record" ON public.users FOR ALL USING (id = auth.uid());

DROP POLICY IF EXISTS "All users can access their own company data" ON public.company_settings;
CREATE POLICY "All users can access their own company data" ON public.company_settings FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.inventory;
CREATE POLICY "All users can access their own company data" ON public.inventory FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.suppliers;
CREATE POLICY "All users can access their own company data" ON public.suppliers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.sales;
CREATE POLICY "All users can access their own company data" ON public.sales FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.sale_items;
CREATE POLICY "All users can access their own company data" ON public.sale_items FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.customers;
CREATE POLICY "All users can access their own company data" ON public.customers FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.conversations;
CREATE POLICY "All users can access their own company data" ON public.conversations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.messages;
CREATE POLICY "All users can access their own company data" ON public.messages FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.integrations;
CREATE POLICY "All users can access their own company data" ON public.integrations FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));

DROP POLICY IF EXISTS "All users can access their own company data" ON public.inventory_ledger;
CREATE POLICY "All users can access their own company data" ON public.inventory_ledger FOR ALL USING (company_id = (SELECT company_id FROM public.users WHERE id = auth.uid()));


-- Create a serial sequence if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'serial') THEN
        CREATE SEQUENCE public.serial START 1;
    END IF;
END $$;
