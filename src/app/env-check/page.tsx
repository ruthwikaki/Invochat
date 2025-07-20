'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { signOut } from '@/app/(auth)/actions';


export default function EnvCheckPage() {
    
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
              <div className="text-left p-4 bg-muted rounded-md border text-sm">
                  <p>1. In your project, find the file located at: <code className="font-mono bg-muted-foreground/20 px-1 py-0.5 rounded-sm">src/lib/database-schema.sql</code></p>
                  <p>2. Copy the entire contents of this file.</p>
                  <p>3. Go to your Supabase project dashboard and navigate to the <span className="font-semibold">SQL Editor</span>.</p>
                  <p>4. Paste the copied SQL code into the editor and click <span className="font-semibold">"Run"</span>.</p>
              </div>
            </CardContent>
            <CardFooter className="flex-col gap-4">
                <p className="text-sm text-muted-foreground text-center">
                    After running the SQL script in your Supabase project, you must sign out and sign up with a <strong>new user account</strong>. This new account will be correctly configured by the trigger you just created.
                </p>
                <form action={signOut} className="w-full">
                  <Button variant="outline" type="submit" className="w-full">
                      <LogOut className="mr-2 h-4 w-4" />
                      Sign Out and Create New Account
                  </Button>
                </form>
            </CardFooter>
          </Card>
        </div>
    );
}
