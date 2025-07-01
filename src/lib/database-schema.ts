
-- InvoChat Database Setup Script
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


-- ========= Part 5: E-Commerce & Integration Tables =========

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
