
import { SETUP_SQL_SCRIPT } from '@/lib/database-schema';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';


// Note: This component is duplicated in src/app/env-check/page.tsx
// to avoid circular dependencies and to present a consistent UI for setup issues.
function SetupInstructions() {
    const { toast } = useToast();

    const copyToClipboard = () => {
        navigator.clipboard.writeText(SETUP_SQL_SCRIPT).then(() => {
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

    const handleSignOut = () => {
        // Simplified sign out for this specific error page.
        window.location.href = '/login';
    };

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
                    <code>{SETUP_SQL_SCRIPT}</code>
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


export default function SetupIncompletePage() {
  return <SetupInstructions />;
}

```
