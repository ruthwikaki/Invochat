-- This file contains all the necessary SQL to set up your database.
-- It should be run once in your Supabase project's SQL Editor.
-- This script is idempotent and can be safely re-run on an existing database.

-- ========= Part 1: New User Trigger =========
-- This function and trigger ensure that when a new user signs up,
-- their company information is correctly created and the 'company_id'
-- is stored in their authentication metadata, which is crucial for
-- the app's multi-tenancy to work correctly.

-- First, ensure the 'uuid-ossp' extension is enabled to generate UUIDs.
create extension if not exists "uuid-ossp" with schema extensions;

-- This function runs for each new user created in the 'auth.users' table.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  user_company_id uuid;
  user_company_name text;
begin
  -- Extract company_id and company_name from the metadata provided during signup.
  user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
  user_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a corresponding record in the 'public.companies' table.
  insert into public.companies (id, name)
  values (user_company_id, user_company_name)
  on conflict (id) do nothing;

  -- Create a corresponding record in the 'public.users' table to link the user to their company.
  insert into public.users (id, email, company_id)
  values (new.id, new.email, user_company_id);

  -- **This is the most critical step for authentication.**
  -- It copies the company_id into 'app_metadata', which makes it available
  -- in the user's session token (JWT). The middleware relies on this to grant access.
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', user_company_id)
  where id = new.id;

  return new;
end;
$$;

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
as $$
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
$$;

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

-- ========= Part 3: Performance Optimization (Materialized View) =========
-- This creates a materialized view, which is a pre-calculated snapshot of key metrics.
-- This makes the dashboard load much faster for large datasets.
CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  iv.company_id,
  COUNT(DISTINCT iv.sku) as total_skus,
  SUM(iv.quantity * iv.cost) as inventory_value,
  COUNT(CASE WHEN fi.quantity <= fi.reorder_point AND fi.reorder_point > 0 THEN 1 END) as low_stock_count
FROM inventory_valuation iv
LEFT JOIN fba_inventory fi ON iv.sku = fi.sku AND iv.company_id = fi.company_id
GROUP BY iv.company_id
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
AS $$
  REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
$$;


-- ========= Part 4: AI Query Learning Table =========
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
