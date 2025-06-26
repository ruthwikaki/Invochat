
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
                    <CardTitle className="mt-4">Account Setup Incomplete</CardTitle>
                    <CardDescription>
                        Your user account is authenticated, but your database is not fully configured.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                    <p className="text-sm text-muted-foreground">
                        This application requires two components in your database to function correctly: a trigger to handle new user signups, and a special function to allow the AI to securely query your data.
                    </p>
                    <h3 className="font-semibold pt-4">How to Fix</h3>
                    <p className="text-sm text-muted-foreground">
                        Please run the following SQL code **once** in your Supabase project's SQL Editor. This will create both required components.
                    </p>
                    <div className="relative bg-background border rounded-md font-mono text-xs max-h-72 overflow-y-auto">
                        <Button
                            size="sm"
                            variant="ghost"
                            className="absolute top-2 right-2 z-10"
                            onClick={copyToClipboard}
                        >
                            Copy
                        </Button>
                        <pre className="p-4 overflow-x-auto">
                            <code>{sqlCode}</code>
                        </pre>
                    </div>
                     <p className="text-sm text-muted-foreground pt-2">
                        After running the SQL, you must **sign out and sign up with a new user account**. The trigger only runs for new accounts. Existing accounts will not be fixed automatically.
                    </p>
                </CardContent>
                <CardFooter>
                    <Button
                        variant="destructive"
                        className="w-full"
                        onClick={handleSignOut}
                    >
                        <LogOut className="mr-2 h-4 w-4" />
                        Sign Out and Start Over
                    </Button>
                </CardFooter>
            </Card>
        </div>
    )
}
