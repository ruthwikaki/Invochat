
'use client';

import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';

const sqlCode = `-- This file contains all the necessary SQL to set up your database.
-- It should be run once in your Supabase project's SQL Editor.

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

-- ========= Part 3: Performance Optimization (Optional, but Recommended) =========
-- This creates a "materialized view", which is like a pre-calculated snapshot
-- of your key inventory metrics. Querying this view is much faster than
-- calculating the metrics from the raw inventory table every time the dashboard loads.
-- NOTE: This view is based on the 'inventory_valuation' table.

CREATE MATERIALIZED VIEW IF NOT EXISTS public.company_dashboard_metrics AS
SELECT
  company_id,
  COUNT(DISTINCT sku) as total_skus,
  SUM(quantity * cost) as inventory_value,
  -- Note: reorder_point is not in inventory_valuation, so low_stock_count is simplified.
  -- A more complex version could JOIN with another table if reorder points exist there.
  COUNT(CASE WHEN quantity <= 20 THEN 1 END) as low_stock_count
FROM inventory_valuation
GROUP BY company_id
WITH DATA;

-- Create an index to make lookups on the view lightning-fast.
CREATE UNIQUE INDEX IF NOT EXISTS idx_company_dashboard_metrics_company_id
ON public.company_dashboard_metrics(company_id);

-- This function is used to refresh the view with the latest data.
-- You can set up a schedule to run this periodically (e.g., every 5 minutes)
-- using Supabase's pg_cron extension.
-- Example cron job: SELECT cron.schedule('5_minute_refresh', '*/5 * * * *', 'REFRESH MATERIALIZED VIEW public.company_dashboard_metrics');

CREATE OR REPLACE FUNCTION public.refresh_dashboard_metrics()
RETURNS void
LANGUAGE sql
AS $$
  REFRESH MATERIALIZED VIEW public.company_dashboard_metrics;
$$;

-- ========= Part 4: AI Query Learning =========
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
`;


export default function SetupIncompletePage() {
    const { signOut } = useAuth();
    const router = useRouter();
    const { toast } = useToast();

    const handleSignOut = async () => {
        await signOut();
        router.push('/login');
    };

    const copyToClipboard = () => {
        if(navigator.clipboard) {
            navigator.clipboard.writeText(sqlCode);
            toast({ title: "Copied to clipboard!" });
        }
    };

    return (
        <div className="flex items-center justify-center min-h-dvh bg-muted/40 p-4">
            <Card className="w-full max-w-3xl">
                <CardHeader className="text-center">
                    <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
                        <AlertTriangle className="h-8 w-8 text-destructive" />
                    </div>
                    <CardTitle className="mt-4">One-Time Database Setup Required</CardTitle>
                    <CardDescription>
                       To get started, the necessary database functions and triggers must be set up in your Supabase project.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                    <p className="text-sm text-center font-semibold text-destructive bg-destructive/10 p-3 rounded-md">
                        This is a one-time action for the developer setting up this project. Your end-users will not see this page.
                    </p>
                    <div className="space-y-2 text-sm text-muted-foreground">
                        <h3 className="font-semibold text-card-foreground">How to Fix:</h3>
                        <p>1. Click the button below to copy the required SQL setup script.</p>
                        <p>2. Go to your Supabase project's SQL Editor.</p>
                        <p>3. Paste the entire script into the editor and click "Run".</p>
                    </div>

                    <div className="relative bg-background border rounded-md font-mono text-xs max-h-72 overflow-y-auto">
                        <Button
                            size="sm"
                            variant="ghost"
                            className="absolute top-2 right-2 z-10"
                            onClick={copyToClipboard}
                        >
                            Copy SQL
                        </Button>
                        <pre className="p-4 overflow-x-auto">
                            <code>{sqlCode}</code>
                        </pre>
                    </div>
                     <p className="text-sm text-muted-foreground pt-2">
                        <strong className="text-destructive">Important:</strong> The database trigger only works for <strong className="text-destructive">new</strong> user signups. After running the SQL, you must sign out and sign up again with a fresh email account to test the application.
                    </p>
                </CardContent>
                <CardFooter>
                    <Button
                        variant="destructive"
                        className="w-full"
                        onClick={handleSignOut}
                    >
                        <LogOut className="mr-2 h-4 w-4" />
                        Sign Out & Create a New Account
                    </Button>
                </CardFooter>
            </Card>
        </div>
    )
}
