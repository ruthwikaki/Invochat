'use client';

import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { CheckCircle } from 'lucide-react';
import Link from 'next/link';

export default function DatabaseSetupPage() {
  return (
    <AppPage>
        <AppPageHeader
            title="Initial Deployment Setup"
            description="This page is for the initial deployment administrator."
        />
        <Card className="flex flex-col items-center justify-center text-center p-12">
            <CheckCircle className="h-16 w-16 text-success" />
            <CardTitle className="mt-4">Setup Complete</CardTitle>
            <CardDescription className="mt-2">
                The database setup script has already been run. This page is no longer needed.
            </CardDescription>
            <Button asChild className="mt-6">
                <Link href="/dashboard">Go to Dashboard</Link>
            </Button>
        </Card>
    </AppPage>
  );
}
