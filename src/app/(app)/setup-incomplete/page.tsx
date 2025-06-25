
'use client';

import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';

const sqlCode = `-- This function and trigger ensure that when a new user signs up,
-- their company information is correctly created in the database and
-- the 'company_id' is stored in their authentication metadata (app_metadata),
-- which is crucial for the app's multi-tenancy to work correctly.

-- First, ensure the 'uuid-ossp' extension is enabled to generate UUIDs.
create extension if not exists "uuid-ossp";

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
  -- The signup action in the app code generates and passes this data.
  user_company_id := (new.raw_user_meta_data->>'company_id')::uuid;
  user_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a corresponding record in the 'public.companies' table.
  -- 'ON CONFLICT (id) DO NOTHING' prevents errors if a company with this ID already exists.
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
            <Card className="w-full max-w-2xl">
                <CardHeader className="text-center">
                    <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
                        <AlertTriangle className="h-8 w-8 text-destructive" />
                    </div>
                    <CardTitle className="mt-4">Account Setup Incomplete</CardTitle>
                    <CardDescription>
                        Your user account is authenticated, but it's not fully configured in the database.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                    <p className="text-sm text-muted-foreground">
                        This happens when the database trigger that links your user to a company is missing or incorrect. This trigger is essential for the application to work.
                    </p>
                    <h3 className="font-semibold pt-4">How to Fix</h3>
                    <p className="text-sm text-muted-foreground">
                        To permanently fix this, please run the following SQL code in your Supabase project's SQL Editor. This only needs to be done once per project.
                    </p>
                    <div className="relative bg-background border rounded-md font-mono text-xs">
                        <Button
                            size="sm"
                            variant="ghost"
                            className="absolute top-2 right-2"
                            onClick={copyToClipboard}
                        >
                            Copy
                        </Button>
                        <pre className="p-4 overflow-x-auto">
                            <code>{sqlCode}</code>
                        </pre>
                    </div>
                     <p className="text-sm text-muted-foreground pt-2">
                        After running the SQL, you must **sign out and sign up with a new user account**. The trigger only runs for new accounts.
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
