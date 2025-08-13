
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import { useSearchParams } from 'next/navigation';

export default function EnvCheckPage() {
    const searchParams = useSearchParams();
    const error = searchParams.get('error');

    return (
        <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
          <Card className="w-full max-w-2xl">
            <CardHeader>
              <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit mb-4">
                <AlertTriangle className="h-8 w-8 text-destructive" />
              </div>
              <CardTitle className="text-center text-2xl">Database Setup Incomplete</CardTitle>
              <CardDescription className="text-center">
                Your user account exists, but the initial database setup for your company has not been completed.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="text-center space-y-4">
                <p className="text-sm text-muted-foreground">
                    This usually happens if the database schema was not set up correctly before you signed up. To fix this, you need to run the setup script in your Supabase project.
                </p>
                 <div className="text-left p-4 bg-muted rounded-md border text-sm">
                    <p>1. In your project, find the file located at: <code className="font-mono bg-muted-foreground/20 px-1 py-0.5 rounded-sm">src/lib/database-schema.sql</code></p>
                    <p>2. Copy the entire contents of this file.</p>
                    <p>3. Go to your Supabase project dashboard and navigate to the <span className="font-semibold">SQL Editor</span>.</p>
                    <p>4. Paste the copied SQL code into the editor and click <span className="font-semibold">&quot;Run&quot;</span>.</p>
                </div>
                 <p className="text-sm text-muted-foreground">
                    After the script finishes successfully, you must sign out and <span className="font-semibold">create a new user account</span>. This will ensure your new company is set up correctly.
                </p>
                {error && <p className="text-destructive text-sm font-medium">{error}</p>}
              </div>
            </CardContent>
            <CardFooter>
                 <Button asChild className="w-full">
                    <a href="/login">Return to Login</a>
                </Button>
            </CardFooter>
          </Card>
        </div>
    );
}
