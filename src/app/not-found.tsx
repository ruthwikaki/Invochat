
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="flex items-center justify-center min-h-dvh bg-muted/40 p-4">
        <Card className="w-full max-w-md text-center">
            <CardHeader>
                <div className="mx-auto bg-primary/10 p-3 rounded-full w-fit">
                    <AlertTriangle className="h-8 w-8 text-primary" />
                </div>
                <CardTitle className="mt-4 text-4xl font-bold">404</CardTitle>
                <CardDescription className="text-lg">
                    Page Not Found
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
                <p className="text-muted-foreground">
                    Sorry, we couldn&apos;t find the page you were looking for.
                </p>
                <Button asChild>
                  <Link href="/dashboard">Go to Dashboard</Link>
                </Button>
            </CardContent>
        </Card>
    </div>
  );
}
