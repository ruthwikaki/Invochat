
'use client';

import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';

const sqlCode = `-- Creates a company and a user profile for each new user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company_name from metadata passed during signup
  user_company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  insert into public.companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Create a record in your public.users table
  insert into public.users (id, email, company_id)
  values (new.id, new.email, new_company_id);

  -- Update the user's app_metadata in the auth.users table
  -- This makes the company_id available in the user's session
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the function after a new user is created in auth.users
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
                        This usually happens for one of two reasons:
                    </p>
                    <ul className="list-disc list-inside text-sm text-muted-foreground space-y-1">
                        <li>The necessary database trigger (<code>handle_new_user</code>) is missing or incorrect.</li>
                        <li>You signed up with this user account *before* the trigger was added.</li>
                    </ul>
                    <h3 className="font-semibold pt-4">How to Fix</h3>
                    <p className="text-sm text-muted-foreground">
                        To resolve this, please run the following SQL code in your Supabase project's SQL Editor. This only needs to be done once.
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
