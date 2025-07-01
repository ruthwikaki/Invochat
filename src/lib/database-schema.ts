
export const SETUP_SQL_SCRIPT = `-- InvoChat Database Setup Script
-- This script is idempotent and can be safely re-run on an existing database.

-- ========= Part 1: New User Trigger =========
-- This function and trigger ensure that when a new user signs up via email or accepts an invitation,
-- their company information and role are correctly created and stored.

-- First, ensure the 'uuid-ossp' extension is enabled to generate UUIDs.
create extension if not exists "uuid-ossp" with schema extensions;

-- This function runs for each new user created in the 'auth.users' table.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $new_user_func$
declare
  user_company_id uuid;
  user_company_name text;
  user_role text;
  is_invite boolean;
begin
  -- Check if this is an invite acceptance by looking for the invited_at timestamp
  is_invite := new.invited_at IS NOT NULL;

  IF is_invite THEN
    -- This is an invited user. Their company_id is in the metadata from the invite.
    user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    user_role := 'Member';
    
    IF user_company_id IS NULL THEN
      -- This case should not happen if invites are sent correctly, but as a safeguard:
      raise exception 'Invited user must have a company_id in metadata.';
    END IF;
    
  ELSE
    -- This is a new company signup. A new company_id was generated on the client.
    user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
    user_company_name := new.raw_user_meta_data->>'company_name';
    user_role := 'Owner';

    -- Create a corresponding record in the 'public.companies' table.
    -- This is also safe for invites; ON CONFLICT does nothing if the company already exists.
    insert into public.companies (id, name)
    values (user_company_id, user_company_name)
    on conflict (id) do nothing;
  END IF;

  -- Create a corresponding record in the 'public.users' table with the correct role.
  insert into public.users (id, email, company_id, role)
  values (new.id, new.email, user_company_id, user_role);

  -- **This is the most critical step for authentication.**
  -- It copies the company_id into 'app_metadata', which makes it available
  -- in the user's session token (JWT). The middleware relies on this to grant access.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', user_company_id)
  where id = new.id;

  return new;
end;
$new_user_func$;

-- This trigger executes the 'handle_new_user' function automatically
-- every time a new row is inserted into 'auth.users'.
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ========= Part 2: Dynamic Query Function =========
-- This function is CRITICAL for the AI chat functionality.
-- It allows the AI to securely execute read-only queries that your application constructs.
-- It takes a SQL query string as input and returns the result as a JSON array.

create or replace function public.execute_dynamic_query(query_text text)
returns json
language plpgsql
as $dyn_query_func$
declare
  result_json json;
begin
  -- Execute the dynamic query and aggregate the results into a JSON array.
  -- The coalesce function ensures that if the query returns no rows,
  -- we get an empty JSON array '[]' instead of NULL.
  execute format('select coalesce(json_agg(t), ''[]'') from (%s) t', query_text)
  into result_json;

  return result_json;
end;
$dyn_query_func$;


-- ========= Part 3: AI Query Learning Table =========
-- This table stores successful query patterns for each company.
-- The AI uses these as dynamic few-shot examples to learn from
-- past interactions and improve the accuracy of its generated SQL
-- for specific users over time.

CREATE TABLE IF NOT EXISTS public.query_patterns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    user_question text NOT NULL,
    successful_sql_query text NOT NULL,
    usage_count integer DEFAULT 1,
    last_used_at timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    -- A user is unlikely to ask the exact same question in two different ways
    -- that should be stored separately. This constraint ensures we update
    -- the existing pattern rather than creating duplicates.
    CONSTRAINT unique_question_per_company UNIQUE (company_id, user_question)
);

-- Add an index for faster lookups when fetching patterns for a company.
CREATE INDEX IF NOT EXISTS idx_query_patterns_company_id ON public.query_patterns(company_id);


-- ========= Part 4: Transactional Data Import =========
-- This function is used by the Data Importer to perform bulk upserts
-- within a single database transaction. This ensures that if any row
-- in a CSV fails to import, the entire operation is rolled back,
-- preventing partial or corrupt data from being saved.

create or replace function public.batch_upsert_with_transaction(
  p_table_name text,
  p_records jsonb,
  p_conflict_columns text[]
)
returns void
language plpgsql
security definer
as $batch_upsert_func$
declare
  -- Dynamically build the SET clause for the 'ON CONFLICT' part of the upsert.
  -- It constructs a string like "col1 = EXCLUDED.col1, col2 = EXCLUDED.col2, ..."
  -- It excludes the columns used for conflict resolution from being updated.
  update_set_clause text := (
    select string_agg(format('%I = excluded.%I', key, key), ', ')
    from jsonb_object_keys(p_records -> 0) as key
    where not (key = any(p_conflict_columns))
  );
  
  -- The main dynamic SQL statement.
  query text;
begin
  -- Ensure the function only works on specific, whitelisted tables to prevent misuse.
  if p_table_name not in ('inventory', 'vendors', 'supplier_catalogs', 'reorder_rules', 'locations', 'customers', 'orders', 'order_items') then
    raise exception 'Invalid table name provided for batch upsert: %', p_table_name;
  end if;

  -- This query is executed as a single statement, making it more performant than a loop.
  -- It uses \`jsonb_populate_recordset\` to safely convert the JSON array into a set of rows
  -- matching the target table's structure. This is safer than manual value string construction.
  query := format(
    '
    INSERT INTO %I
    SELECT * FROM jsonb_populate_recordset(null::%I, $1)
    ON CONFLICT (%s) DO UPDATE SET %s;
    ',
    p_table_name,
    p_table_name, -- First argument to jsonb_populate_recordset is the table type
    array_to_string(p_conflict_columns, ', '),
    update_set_clause
  );
  
  -- Execute the full query, passing the records as a parameter to prevent SQL injection.
  execute query using p_records;

-- If any exception occurs, the entire transaction is automatically
-- rolled back by PostgreSQL, and the exception is re-raised.
end;
$batch_upsert_func$;


-- ========= Part 5: E-Commerce & Integration Tables =========

-- Add generic integration columns to existing tables
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS source_platform TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_product_id TEXT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS external_variant_id TEXT;
ALTER TABLE public.inventory DROP CONSTRAINT IF EXISTS unique_shopify_variant_per_company;
ALTER TABLE public.inventory ADD CONSTRAINT unique_external_variant_per_company UNIQUE (company_id, source_platform, external_variant_id);


-- Table for customers
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    platform TEXT, -- e.g. 'shopify', 'woocommerce'
    external_id TEXT, -- The ID from the external platform
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
-- Drop old specific constraint and name column
ALTER TABLE public.customers DROP CONSTRAINT IF EXISTS unique_shopify_customer_per_company;
ALTER TABLE public.customers DROP COLUMN IF EXISTS shopify_customer_id;
-- Add new generic unique constraint
ALTER TABLE public.customers ADD CONSTRAINT unique_external_customer_per_company UNIQUE (company_id, platform, external_id);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- Table for sales orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    sale_date TIMESTAMP WITH TIME ZONE NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    sales_channel TEXT,
    platform TEXT, -- e.g. 'shopify', 'woocommerce'
    external_id TEXT, -- The ID from the external platform
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
-- Drop old specific constraint and customer name column
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS unique_shopify_order_per_company;
ALTER TABLE public.orders DROP COLUMN IF EXISTS shopify_order_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS customer_name;
-- Add new generic unique constraint
ALTER TABLE public.orders ADD CONSTRAINT unique_external_order_per_company UNIQUE (company_id, platform, external_id);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_sale_date ON public.orders(sale_date);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);

-- Table for items within a sales order
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_order_items_sale_id ON public.order_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_order_items_sku ON public.order_items(sku);


-- Table for integrations (e.g., Shopify)
CREATE TABLE IF NOT EXISTS public.integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    platform TEXT NOT NULL, -- e.g., 'shopify'
    shop_domain TEXT,
    access_token TEXT, -- Encrypted
    shop_name TEXT,
    is_active BOOLEAN DEFAULT false,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    sync_status TEXT, -- e.g., 'syncing', 'success', 'failed', 'idle'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_platform_per_company UNIQUE (company_id, platform)
);
CREATE INDEX IF NOT EXISTS idx_integrations_company_id ON public.integrations(company_id);

-- Table to log sync history
CREATE TABLE IF NOT EXISTS public.sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES public.integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL, -- e.g., 'products', 'orders'
    status TEXT NOT NULL, -- 'started', 'completed', 'failed'
    records_synced INTEGER,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_sync_logs_integration_id ON public.sync_logs(integration_id);


-- ========= Part 6: Performance Optimization (Materialized View) =========
-- This creates a materialized view, which is a pre-calculated snapshot of key metrics.
-- This makes the dashboard load much faster for large datasets.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  i.company_id,
  COUNT(DISTINCT i.sku) as total_skus,
  SUM(i.quantity * i.cost) as inventory_value,
  COUNT(CASE WHEN i.quantity <= i.reorder_point AND i.reorder_point > 0 THEN 1 END) as low_stock_count
FROM inventory i
GROUP BY i.company_id
WITH DATA;

-- Create an index to make lookups on the view lightning-fast.
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id
ON public.company_dashboard_metrics(company_id);

-- This function is used to refresh the view with the latest data.
-- You can schedule this to run periodically (e.g., every 5 minutes)
-- using Supabase's pg_cron extension.
-- Example cron job: SELECT cron.schedule('refresh_dashboard_metrics', '*/5 * * * *', 'REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics');
CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics()
RETURNS void
LANGUAGE sql
AS $refresh_func$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
$refresh_func$;

-- ========= Part 7: User Preferences and Notifications =========
-- This table stores user-specific settings for notifications,
-- enabling features like the "Morning Coffee Email".
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  email_daily_digest BOOLEAN DEFAULT TRUE,
  email_low_stock BOOLEAN DEFAULT TRUE,
  sms_critical_alerts BOOLEAN DEFAULT FALSE,
  sms_phone_number TEXT,
  digest_time TIME WITH TIME ZONE DEFAULT '07:00:00+00'
);

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_notification_preferences_company_id ON public.notification_preferences(company_id);


-- ========= Part 8: Data Integrity Functions =========

-- Safely deletes a location and unassigns inventory items from it.
create or replace function public.delete_location_and_unassign_inventory(p_location_id uuid, p_company_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  -- Unassign inventory items from this location
  update public.inventory
  set location_id = null
  where location_id = p_location_id and company_id = p_company_id;

  -- Delete the location
  delete from public.locations
  where id = p_location_id and company_id = p_company_id;
end;
$$;


-- Safely deletes a supplier after checking for dependencies.
create or replace function public.delete_supplier_and_catalogs(p_supplier_id uuid, p_company_id uuid)
returns void
language plpgsql
security definer
as $$
begin
  -- First, check for associated purchase orders. If they exist, raise an error.
  if exists (
    select 1 from public.purchase_orders
    where supplier_id = p_supplier_id and company_id = p_company_id
  ) then
    raise exception 'Cannot delete supplier with active purchase orders.';
  end if;
  
  -- Delete associated supplier catalogs
  delete from public.supplier_catalogs
  where supplier_id = p_supplier_id;

  -- Delete the supplier
  delete from public.vendors
  where id = p_supplier_id and company_id = p_company_id;
end;
$$;


-- ========= Part 9: New Parameterized RPC Functions for Security =========

-- Securely fetches unified inventory data, preventing SQL injection.
CREATE OR REPLACE FUNCTION public.get_unified_inventory(p_company_id uuid, p_query text, p_category text, p_location_id uuid)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    WITH monthly_sales AS (
        SELECT 
            oi.sku,
            SUM(oi.quantity) as units_sold
        FROM order_items oi
        JOIN orders o ON oi.sale_id = o.id
        WHERE o.company_id = p_company_id AND o.sale_date >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY oi.sku
    )
    SELECT coalesce(json_agg(t), '[]')
    INTO result_json
    FROM (
        SELECT
            i.sku,
            i.name as product_name,
            i.category,
            i.quantity,
            i.cost,
            i.price,
            (i.quantity * i.cost) as total_value,
            i.reorder_point,
            i.on_order_quantity,
            i.landed_cost,
            i.barcode,
            i.location_id,
            l.name as location_name,
            COALESCE(ms.units_sold, 0) as monthly_units_sold,
            ((i.price - COALESCE(i.landed_cost, i.cost)) * COALESCE(ms.units_sold, 0)) as monthly_profit
        FROM inventory i
        LEFT JOIN locations l ON i.location_id = l.id
        LEFT JOIN monthly_sales ms ON i.sku = ms.sku
        WHERE i.company_id = p_company_id
        AND (p_query IS NULL OR (i.name ILIKE '%' || p_query || '%' OR i.sku ILIKE '%' || p_query || '%'))
        AND (p_category IS NULL OR i.category = p_category)
        AND (p_location_id IS NULL OR i.location_id = p_location_id)
        ORDER BY i.name
    ) t;

    RETURN result_json;
END;
$$;

-- Securely fetches historical sales for a given list of SKUs.
CREATE OR REPLACE FUNCTION public.get_historical_sales(p_company_id uuid, p_skus text[])
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]')
    INTO result_json
    FROM (
        SELECT
            sku,
            json_agg(json_build_object('month', sales_month, 'total_quantity', total_quantity) ORDER BY sales_month) as monthly_sales
        FROM (
            SELECT
                oi.sku,
                TO_CHAR(DATE_TRUNC('month', o.sale_date), 'YYYY-MM') as sales_month,
                SUM(oi.quantity) as total_quantity
            FROM order_items oi
            JOIN orders o ON oi.sale_id = o.id
            WHERE o.company_id = p_company_id
            AND oi.sku = ANY(p_skus)
            AND o.sale_date >= CURRENT_DATE - INTERVAL '24 months'
            GROUP BY oi.sku, DATE_TRUNC('month', o.sale_date)
        ) as monthly_data
        GROUP BY sku
    ) t;

    RETURN result_json;
END;
$$;


-- ========= Part 10: Inventory Ledger System =========
-- The core of inventory tracking. Every stock movement is recorded here.

CREATE TABLE IF NOT EXISTS public.inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sku text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    change_type text NOT NULL, -- e.g., 'purchase_order_received', 'sale', 'return', 'manual_adjustment'
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., purchase_order_id or order_id
    notes text
);
CREATE INDEX IF NOT EXISTS idx_inventory_ledger_company_sku ON public.inventory_ledger(company_id, sku, created_at DESC);


-- Helper function to create ledger entries atomically.
CREATE OR REPLACE FUNCTION public.create_inventory_ledger_entry(
  p_company_id uuid,
  p_sku text,
  p_change_type text,
  p_quantity_change integer,
  p_related_id uuid DEFAULT null,
  p_notes text DEFAULT null
) RETURNS void AS $$
DECLARE
    current_quantity_val int;
BEGIN
    -- Get current quantity from inventory table
    SELECT quantity INTO current_quantity_val
    FROM public.inventory
    WHERE sku = p_sku AND company_id = p_company_id;

    -- Insert into the ledger
    INSERT INTO public.inventory_ledger (company_id, sku, change_type, quantity_change, new_quantity, related_id, notes)
    VALUES (p_company_id, p_sku, p_change_type, p_quantity_change, current_quantity_val, p_related_id, p_notes);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to decrement inventory for a sale and create a ledger entry.
CREATE OR REPLACE FUNCTION public.process_sales_order_inventory(
    p_order_id uuid,
    p_company_id uuid
) RETURNS void AS $$
DECLARE
    order_item record;
BEGIN
    FOR order_item IN
        SELECT sku, quantity FROM public.order_items WHERE sale_id = p_order_id
    LOOP
        -- Decrement inventory
        UPDATE public.inventory
        SET quantity = quantity - order_item.quantity
        WHERE sku = order_item.sku AND company_id = p_company_id;

        -- Create ledger entry for the sale
        PERFORM public.create_inventory_ledger_entry(p_company_id, order_item.sku, 'sale', -order_item.quantity, p_order_id);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Overwrite the existing RPC function to include ledger entries
CREATE OR REPLACE FUNCTION public.receive_purchase_order_items(p_po_id uuid, p_items_to_receive jsonb, p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    item jsonb;
    current_po_status text;
    total_ordered integer;
    total_received integer;
BEGIN
    -- Loop through each item in the JSON array
    FOR item IN SELECT * FROM jsonb_array_elements(p_items_to_receive)
    LOOP
        -- Update the quantity received for the specific item on the purchase order
        UPDATE public.purchase_order_items
        SET quantity_received = quantity_received + (item->>'quantity_to_receive')::integer
        WHERE po_id = p_po_id AND sku = item->>'sku';

        -- Update the main inventory table
        UPDATE public.inventory
        SET quantity = quantity + (item->>'quantity_to_receive')::integer,
            on_order_quantity = on_order_quantity - (item->>'quantity_to_receive')::integer
        WHERE company_id = p_company_id AND sku = item->>'sku';
        
        -- Create a ledger entry for this stock movement
        PERFORM public.create_inventory_ledger_entry(
            p_company_id,
            item->>'sku',
            'purchase_order_received',
            (item->>'quantity_to_receive')::integer,
            p_po_id
        );
    END LOOP;

    -- After updating all items, check if the PO is now fully or partially received
    SELECT
        SUM(quantity_ordered),
        SUM(quantity_received)
    INTO
        total_ordered,
        total_received
    FROM public.purchase_order_items
    WHERE po_id = p_po_id;

    IF total_received >= total_ordered THEN
        current_po_status := 'received';
    ELSIF total_received > 0 THEN
        current_po_status := 'partial';
    ELSE
        -- If no items have been received, keep the original status
        SELECT status INTO current_po_status FROM public.purchase_orders WHERE id = p_po_id;
    END IF;

    -- Update the main purchase order status
    UPDATE public.purchase_orders
    SET status = current_po_status,
        updated_at = NOW()
    WHERE id = p_po_id;
END;
$$;


-- Function to get the full ledger history for a specific product
CREATE OR REPLACE FUNCTION public.get_inventory_ledger_for_sku(p_company_id uuid, p_sku text)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    result_json json;
BEGIN
    SELECT coalesce(json_agg(t), '[]')
    INTO result_json
    FROM (
        SELECT *
        FROM public.inventory_ledger
        WHERE company_id = p_company_id AND sku = p_sku
        ORDER BY created_at DESC
        LIMIT 100
    ) t;

    RETURN result_json;
END;
$$;
`;
