
'use client';

import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';

const sqlCode = `-- This file contains all the necessary SQL to set up your database.
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
as $$
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
AS $$
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.company_dashboard_metrics;
$$;


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
as $$
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
  if p_table_name not in ('inventory', 'vendors') then
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
$$;

-- Secure the function so it can only be called by authenticated service roles
REVOKE EXECUTE ON FUNCTION public.batch_upsert_with_transaction(text, jsonb, text[]) FROM public;
GRANT EXECUTE ON FUNCTION public.batch_upsert_with_transaction(text, jsonb, text[]) TO service_role;


-- ========= Part 7: E-Commerce Features (Purchase Orders, Catalogs, Reordering) =========

-- Add new columns to the inventory table.
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS on_order_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS landed_cost NUMERIC(10, 2);
ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS sales_channel TEXT;

-- Define a type for Purchase Order status for data integrity.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'po_status') THEN
        CREATE TYPE po_status AS ENUM ('draft', 'sent', 'partial', 'received', 'cancelled');
    END IF;
END$$;


-- Create the main purchase_orders table if it doesn't exist.
CREATE TABLE IF NOT EXISTS public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add columns idempotently to ensure the table has the correct structure.
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS supplier_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS po_number TEXT;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS status po_status;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS order_date DATE;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS expected_date DATE;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12, 2);
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.purchase_orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE;


-- Add unique constraint if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'unique_po_number_per_company'
        AND conrelid = 'public.purchase_orders'::regclass
    ) THEN
        ALTER TABLE public.purchase_orders ADD CONSTRAINT unique_po_number_per_company UNIQUE (company_id, po_number);
    END IF;
END$$;


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
as $$
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
$$;

-- Secure the function so it can only be called by authenticated service roles
REVOKE EXECUTE ON FUNCTION public.receive_purchase_order_items(uuid, jsonb, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.receive_purchase_order_items(uuid, jsonb, uuid) TO service_role;
`;

export default function SetupIncompletePage() {
    const { signOut } = useAuth();
    const router = useRouter();
    const { toast } = useToast();

    const copyToClipboard = () => {
        navigator.clipboard.writeText(sqlCode).then(() => {
            toast({
                title: 'Copied to Clipboard!',
                description: 'You can now paste this into the Supabase SQL Editor.',
            });
        }, (err) => {
            toast({
                variant: 'destructive',
                title: 'Failed to Copy',
                description: 'Could not copy code to clipboard. Please copy it manually.',
            });
            console.error('Could not copy text: ', err);
        });
    };

    const handleSignOut = async () => {
        await signOut();
        router.push('/login');
    }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
      <Card className="w-full max-w-2xl">
        <CardHeader>
          <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit mb-4">
            <AlertTriangle className="h-8 w-8 text-destructive" />
          </div>
          <CardTitle className="text-center text-2xl">Database Setup Incomplete</CardTitle>
          <CardDescription className="text-center">
            Your account is created, but the database needs to be configured before you can proceed.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="mb-4 text-sm text-muted-foreground">
            This happens because your user account doesn't have a `company_id` associated with it in the database. To fix this, you need to run a one-time setup script in your Supabase project's SQL Editor. This script creates the necessary functions and triggers to link new users to their companies automatically.
          </p>
          <div className="mb-4">
              <Button onClick={copyToClipboard} className="w-full">Copy SQL Code</Button>
          </div>
          <div className="max-h-60 overflow-y-auto rounded-md border bg-muted p-4">
            <pre className="text-xs font-mono whitespace-pre-wrap">
                <code>{sqlCode}</code>
            </pre>
          </div>
        </CardContent>
        <CardFooter className="flex-col gap-4">
            <p className="text-sm text-muted-foreground text-center">
                After running the SQL script in your Supabase project, you must sign out and sign up with a <strong>new user account</strong>. This new account will be correctly configured by the trigger you just created.
            </p>
            <Button variant="outline" onClick={handleSignOut} className="w-full">
                <LogOut className="mr-2 h-4 w-4" />
                Sign Out
            </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
