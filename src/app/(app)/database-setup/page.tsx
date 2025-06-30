'use client';

import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { DatabaseZap, Copy } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { SETUP_SQL_SCRIPT } from '@/lib/database-schema';

const sqlCode = SETUP_SQL_SCRIPT;

export default function DatabaseSetupPage() {
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

  return (
    <AppPage>
        <AppPageHeader
            title="Database Setup Script"
            description="Run this one-time script in your Supabase SQL Editor to configure your database."
        />
        <Card>
            <CardHeader>
                <CardTitle className="flex items-center gap-2">
                    <DatabaseZap className="h-6 w-6 text-primary"/>
                    Complete Setup Script
                </CardTitle>
                <CardDescription>
                    This single script contains all the tables, functions, and permissions needed for the application to work correctly. It is safe to run this script multiple times.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <div className="max-h-[50vh] overflow-y-auto rounded-md border bg-muted p-4">
                    <pre className="text-xs font-mono whitespace-pre-wrap">
                        <code>{sqlCode}</code>
                    </pre>
                </div>
            </CardContent>
            <CardFooter>
                <Button onClick={copyToClipboard} className="w-full md:w-auto">
                    <Copy className="mr-2 h-4 w-4" />
                    Copy SQL to Clipboard
                </Button>
            </CardFooter>
      </Card>
    </AppPage>
  );
}
