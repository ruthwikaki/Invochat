
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import Link from 'next/link';
import { Button } from '@/components/ui/button';

export default function DatabaseSetupPage() {

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-2xl">
        <CardHeader>
            <div className="mx-auto bg-primary/10 p-3 rounded-full w-fit mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-8 w-8 text-primary"><path d="M12 2L2 7l10 5 10-5-10-5z"></path><path d="M2 17l10 5 10-5"></path><path d="M2 12l10 5 10-5"></path></svg>
            </div>
            <CardTitle className="text-center text-2xl">Final Database Setup Step</CardTitle>
            <CardDescription className="text-center">
            To get your app running, you need to set up the database schema.
            </CardDescription>
        </CardHeader>
        <CardContent className="text-center space-y-4">
            <p className="text-sm text-muted-foreground">
                You must run a one-time setup script in your Supabase project's SQL Editor. This script creates all the necessary tables, functions, and security policies for the app to work correctly.
            </p>
            <div className="text-left p-4 bg-muted rounded-md border text-sm">
                <p>1. In your project, find the file located at: <code className="font-mono bg-muted-foreground/20 px-1 py-0.5 rounded-sm">src/lib/database-schema.sql</code></p>
                <p>2. Copy the entire contents of this file.</p>
                <p>3. Go to your Supabase project dashboard and navigate to the <span className="font-semibold">SQL Editor</span>.</p>
                <p>4. Paste the copied SQL code into the editor and click <span className="font-semibold">"Run"</span>.</p>
            </div>
             <p className="text-sm text-muted-foreground">
                After the script finishes successfully, you can sign up for a new account.
            </p>
        </CardContent>
        <CardFooter className="flex-col gap-4">
             <Button asChild className="w-full">
                <Link href="/signup">Go to Sign Up Page</Link>
            </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
