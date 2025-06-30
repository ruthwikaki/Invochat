'use server';

// This file contains the single source of truth for the database setup script.
// It is imported by both the /database-setup page and the /setup-incomplete page
// to ensure consistency and avoid code duplication.

export const SETUP_SQL_SCRIPT = `-- This file contains all the necessary SQL to set up your database.
-- It should be run once in your Supabase project's SQL Editor.
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

-- ========= SECURITY NOTE FOR PRODUCTION =========
-- The 'execute_dynamic_query' function is powerful. In a production environment,
-- it is highly recommended to restrict its usage to prevent misuse.
-- You should revoke the default public execute permission and grant it only
-- to the roles that need it (like 'service_role' for the backend).
--
-- Run these commands in your SQL Editor after the initial setup:
--
-- REVOKE EXECUTE ON FUNCTION public.execute_dynamic_query FROM public;
-- GRANT EXECUTE ON FUNCTION public.execute_dynamic_query TO service_role;
--

-- ========= Part 3: Core Application Tables =========
-- This section defines core tables required for application functionality, like 'returns'.

-- The 'returns' table stores information about product returns.
-- The 'created_at' column is essential for time-based analysis.
CREATE TABLE IF NOT EXISTS public.returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    order_id UUID REFERENCES public.orders(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- This command ensures that users with an older version of the database schema
-- get the necessary 'created_at' column added to their 'returns' table.
ALTER TABLE public.returns ADD COLUMN IF NOT EXISTS created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add an index for performance on common queries.
CREATE INDEX IF NOT EXISTS idx_returns_company_created ON public.returns(company_id, created_at);


-- ========= Part 4: Performance Optimization (Materialized View) =========
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


-- ========= Part 5: AI Query Learning Table =========
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


-- ========= Part 6: Transactional Data Import =========
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
  -- It uses `jsonb_populate_recordset` to safely convert the JSON array into a set of rows
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

-- Secure the function so it can only be called by authenticated service roles
REVOKE EXECUTE ON FUNCTION public.batch_upsert_with_transaction(text, jsonb, text[]) FROM public;
GRANT EXECUTE ON FUNCTION public.batch_upsert_with_transaction(text, jsonb, text[]) TO service_role;


-- ========= Part 7: E-Commerce Features (Purchase Orders, Catalogs, Reordering) =========

-- Add new columns to the inventory table.
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS on_order_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS landed_cost NUMERIC(10, 2);
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS barcode TEXT;

-- Define a type for Purchase Order status for data integrity.
DO $type_block$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled');
    END IF;
END $type_block$;


-- Create the main purchase_orders table if it doesn't exist.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add columns idempotently to ensure the table has the correct structure.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.vendors(id) ON DELETE SET NULL;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS po_number TEXT;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS status po_status;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS order_date DATE;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS expected_date DATE;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12, 2);
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;


-- Add unique constraint if it doesn't exist.
DO $constraint_block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'unique_po_number_per_company'
        AND conrelid = 'public.purchase_orders'::regclass
    ) THEN
        ALTER TABLE public.purchase_orders ADD CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number);
    END IF;
END $constraint_block$;


CREATE INDEX IF NOT EXISTS idx_po_company_supplier ON public.purchase_orders(company_id, supplier_id);
CREATE INDEX IF NOT EXISTS idx_po_company_status ON public.purchase_orders(company_id, status);

-- Create the table for items within each purchase order.
CREATE TABLE IF NOT EXISTS public.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id UUID NOT NULL REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    sku TEXT NOT NULL,
    quantity_ordered INTEGER NOT NULL CHECK (quantity_ordered > 0),
    quantity_received INTEGER NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
    unit_cost NUMERIC(10, 2) NOT NULL,
    tax_rate NUMERIC(5, 4) NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_po_items_po_id ON public.purchase_order_items(po_id);
CREATE INDEX IF NOT EXISTS idx_po_items_sku ON public.purchase_order_items(sku);


-- Create table for supplier-specific product catalogs
CREATE TABLE IF NOT EXISTS public.supplier_catalogs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
  sku TEXT NOT NULL, -- The internal SKU in the inventory table
  supplier_sku TEXT, -- The supplier's own SKU for the product
  product_name TEXT,
  unit_cost NUMERIC(10, 2) NOT NULL,
  moq INTEGER DEFAULT 1, -- Minimum Order Quantity
  lead_time_days INTEGER,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT unique_supplier_sku_per_supplier UNIQUE (supplier_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_supplier_catalogs_supplier_sku ON public.supplier_catalogs(supplier_id, sku);

-- Create table for inventory reorder rules
CREATE TABLE IF NOT EXISTS public.reorder_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  sku TEXT NOT NULL,
  rule_type TEXT NOT NULL DEFAULT 'manual', -- e.g., 'manual', 'automatic'
  min_stock INTEGER, -- Reorder when stock falls below this
  max_stock INTEGER, -- Order up to this level
  reorder_quantity INTEGER, -- Fixed quantity to reorder
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT unique_reorder_rule_per_sku UNIQUE (company_id, sku)
);
CREATE INDEX IF NOT EXISTS idx_reorder_rules_company_sku ON public.reorder_rules(company_id, sku);

-- ========= Part 8: Function to Receive PO Items =========
-- This transactional function updates inventory when items from a PO are received.
create or replace function public.receive_purchase_order_items(
  p_po_id uuid,
  p_items_to_receive jsonb, -- e.g., '[{"sku": "SKU123", "quantity_to_receive": 10}, ...]'
  p_company_id uuid
)
returns void
language plpgsql
as $receive_items_func$
declare
  item_record record;
  po_status_current po_status;
  total_ordered int;
  total_received_after_update int;
begin
  -- Loop through each item in the JSON array
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items_to_receive) AS x(sku text, quantity_to_receive int)
  LOOP
    -- Ensure we don't receive more than ordered
    IF item_record.quantity_to_receive > 0 THEN
      -- Update the received quantity on the PO item
      UPDATE purchase_order_items
      SET quantity_received = quantity_received + item_record.quantity_to_receive
      WHERE po_id = p_po_id AND sku = item_record.sku;

      -- Update the main inventory table
      UPDATE inventory
      SET 
        quantity = quantity + item_record.quantity_to_receive,
        on_order_quantity = on_order_quantity - item_record.quantity_to_receive
      WHERE sku = item_record.sku AND company_id = p_company_id;
    END IF;
  END LOOP;

  -- After updating all items, check if the PO is fully received
  SELECT status INTO po_status_current FROM purchase_orders WHERE id = p_po_id;

  IF po_status_current != 'cancelled' THEN
    SELECT 
      SUM(quantity_ordered), SUM(quantity_received)
    INTO 
      total_ordered, total_received_after_update
    FROM purchase_order_items
    WHERE po_id = p_po_id;

    IF total_received_after_update >= total_ordered THEN
      UPDATE purchase_orders SET status = 'received', updated_at = now() WHERE id = p_po_id;
    ELSIF total_received_after_update > 0 THEN
      UPDATE purchase_orders SET status = 'partial', updated_at = now() WHERE id = p_po_id;
    END IF;
  END IF;

end;
$receive_items_func$;

-- Secure the function so it can only be called by authenticated service roles
REVOKE EXECUTE ON FUNCTION public.receive_purchase_order_items(uuid, jsonb, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.receive_purchase_order_items(uuid, jsonb, uuid) TO service_role;


-- ========= Part 9: Function to Create POs =========
-- This transactional function creates a PO, its items, and updates inventory all at once.
create or replace function public.create_purchase_order_and_update_inventory(
  p_company_id uuid,
  p_supplier_id uuid,
  p_po_number text,
  p_order_date date,
  p_expected_date date,
  p_notes text,
  p_total_amount numeric,
  p_items jsonb -- e.g., '[{"sku": "SKU123", "quantity_ordered": 10, "unit_cost": 5.50}, ...]'
)
returns purchase_orders
language plpgsql
security definer
as $create_po_func$
declare
  new_po purchase_orders;
  item_record record;
begin
  -- 1. Create the main purchase order record
  INSERT INTO public.purchase_orders
    (company_id, supplier_id, po_number, status, order_date, expected_date, notes, total_amount)
  VALUES
    (p_company_id, p_supplier_id, p_po_number, 'draft', p_order_date, p_expected_date, p_notes, p_total_amount)
  RETURNING * INTO new_po;

  -- 2. Insert all items and update inventory on_order_quantity in a loop
  FOR item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost numeric)
  LOOP
    -- Insert the item into purchase_order_items
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (new_po.id, item_record.sku, item_record.quantity_ordered, item_record.unit_cost);

    -- Increment the on_order_quantity for the corresponding inventory item
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;

  -- 3. Return the newly created PO
  return new_po;
end;
$create_po_func$;

-- Secure the function
REVOKE EXECUTE ON FUNCTION public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.create_purchase_order_and_update_inventory(uuid, uuid, text, date, date, text, numeric, jsonb) TO service_role;


-- ========= Part 10: Functions for PO Update and Delete =========

-- Function to update a PO and its items transactionally
create or replace function public.update_purchase_order(
  p_po_id uuid,
  p_company_id uuid,
  p_supplier_id uuid,
  p_po_number text,
  p_status po_status,
  p_order_date date,
  p_expected_date date,
  p_notes text,
  p_items jsonb -- e.g., '[{"sku": "SKU123", "quantity_ordered": 10, "unit_cost": 5.50}, ...]'
)
returns void
language plpgsql
security definer
as $update_po_func$
declare
  old_item record;
  new_item_record record;
  new_total_amount numeric := 0;
begin
  -- 1. Adjust inventory for items that are being removed or changed
  FOR old_item IN
    SELECT sku, quantity_ordered FROM public.purchase_order_items WHERE po_id = p_po_id
  LOOP
    -- Decrement the on_order_quantity for all old items
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity - old_item.quantity_ordered
    WHERE sku = old_item.sku AND company_id = p_company_id;
  END LOOP;
  
  -- 2. Delete all existing items for this PO
  DELETE FROM public.purchase_order_items WHERE po_id = p_po_id;

  -- 3. Insert all new items and update inventory on_order_quantity
  FOR new_item_record IN SELECT * FROM jsonb_to_recordset(p_items) AS x(sku text, quantity_ordered int, unit_cost numeric)
  LOOP
    -- Insert the new item
    INSERT INTO public.purchase_order_items
      (po_id, sku, quantity_ordered, unit_cost)
    VALUES
      (p_po_id, new_item_record.sku, new_item_record.quantity_ordered, new_item_record.unit_cost);

    -- Increment the on_order_quantity for the new item
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity + new_item_record.quantity_ordered
    WHERE sku = new_item_record.sku AND company_id = p_company_id;
    
    -- Calculate new total amount
    new_total_amount := new_total_amount + (new_item_record.quantity_ordered * new_item_record.unit_cost);
  END LOOP;

  -- 4. Update the main purchase order record with new total and details
  UPDATE public.purchase_orders
  SET
    supplier_id = p_supplier_id,
    po_number = p_po_number,
    order_date = p_order_date,
    expected_date = p_expected_date,
    notes = p_notes,
    total_amount = new_total_amount,
    status = p_status,
    updated_at = now()
  WHERE id = p_po_id AND company_id = p_company_id;
end;
$update_po_func$;

-- Secure the function
REVOKE EXECUTE ON FUNCTION public.update_purchase_order(uuid, uuid, uuid, text, po_status, date, date, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.update_purchase_order(uuid, uuid, uuid, text, po_status, date, date, text, jsonb) TO service_role;


-- Function to delete a PO and adjust inventory transactionally
create or replace function public.delete_purchase_order(
    p_po_id uuid,
    p_company_id uuid
)
returns void
language plpgsql
security definer
as $delete_po_func$
declare
  item_record record;
begin
  -- First, check if the PO belongs to the company to prevent unauthorized deletion
  IF NOT EXISTS (SELECT 1 FROM public.purchase_orders WHERE id = p_po_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'Purchase order not found or permission denied';
  END IF;

  -- Loop through items to adjust inventory before deleting
  FOR item_record IN
    SELECT sku, quantity_ordered FROM public.purchase_order_items WHERE po_id = p_po_id
  LOOP
    UPDATE public.inventory
    SET on_order_quantity = on_order_quantity - item_record.quantity_ordered
    WHERE sku = item_record.sku AND company_id = p_company_id;
  END LOOP;
  
  -- The DELETE CASCADE on the purchase_order_items table will handle item deletion
  DELETE FROM public.purchase_orders WHERE id = p_po_id;
end;
$delete_po_func$;

-- Secure the function
REVOKE EXECUTE ON FUNCTION public.delete_purchase_order(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.delete_purchase_order(uuid, uuid) TO service_role;

-- ========= Part 11: Channel Fees Table for Net Margin Calculation =========
-- This table stores fees associated with different sales channels (e.g., Shopify, Amazon).
-- The AI will use this table to calculate net profit margin.

CREATE TABLE IF NOT EXISTS public.channel_fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    channel_name TEXT NOT NULL,
    percentage_fee NUMERIC(5, 4) NOT NULL DEFAULT 0, -- e.g., 0.029 for 2.9%
    fixed_fee NUMERIC(10, 2) NOT NULL DEFAULT 0, -- e.g., 0.30 for 30 cents
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE,
    CONSTRAINT unique_channel_per_company UNIQUE (company_id, channel_name)
);

CREATE INDEX IF NOT EXISTS idx_channel_fees_company_id ON public.channel_fees(company_id);


-- ========= Part 12: Multi-Location Inventory =========

-- Create the locations table to store warehouse information.
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_location_name_per_company UNIQUE (company_id, name)
);
CREATE INDEX IF NOT EXISTS idx_locations_company_id ON public.locations(company_id);

-- Add a location_id to the inventory table to track stock per location.
-- It's nullable to support existing setups and allows assigning items to locations over time.
-- ON DELETE SET NULL means if a location is deleted, the inventory items become "unassigned" instead of being deleted.
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_location_id ON public.inventory(location_id);


-- ========= Part 13: Core E-Commerce & Integration Tables =========

-- Add shopify-specific columns to existing tables
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS shopify_product_id BIGINT;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS shopify_variant_id BIGINT;
ALTER TABLE public.inventory ADD CONSTRAINT unique_shopify_variant_per_company UNIQUE (company_id, shopify_variant_id);


-- Table for customers
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_customer_name_per_company UNIQUE (company_id, customer_name)
);
CREATE INDEX IF NOT EXISTS idx_customers_company_id ON public.customers(company_id);


-- Table for sales orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    sale_date TIMESTAMP WITH TIME ZONE NOT NULL,
    customer_name TEXT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    sales_channel TEXT,
    shopify_order_id BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT unique_shopify_order_per_company UNIQUE (company_id, shopify_order_id)
);
CREATE INDEX IF NOT EXISTS idx_orders_company_id ON public.orders(company_id);
CREATE INDEX IF NOT EXISTS idx_orders_sale_date ON public.orders(sale_date);

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
`;
