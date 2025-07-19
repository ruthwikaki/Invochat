
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useToast } from '@/hooks/use-toast';
import { signOut } from '@/app/(auth)/actions';


export default function EnvCheckPage() {
    const router = useRouter();
    
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
                This happens because your user account doesn't have a `company_id` associated with it in the database. This usually means the initial database setup script has not been run in your Supabase project. This script creates the necessary functions and triggers to link new users to their companies automatically.
              </p>
            </CardContent>
            <CardFooter className="flex-col gap-4">
                <p className="text-sm text-muted-foreground text-center">
                    After ensuring the database is correctly set up in your Supabase project, you must sign out and sign up with a <strong>new user account</strong>. This new account will be correctly configured by the database trigger.
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
