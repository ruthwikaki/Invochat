
'use client';

import Link from 'next/link';
import { InvoChatLogo } from '@/components/invochat-logo';
import { Button } from '@/components/ui/button';
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from '@/components/ui/card';

export default function Home() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-muted/40 p-4">
      <div className="mb-8 flex items-center gap-2 text-2xl font-semibold">
        <InvoChatLogo className="h-8 w-8" />
        <h1>InvoChat</h1>
      </div>
      <Card className="w-full max-w-sm text-center">
        <CardHeader>
            <CardTitle>Welcome to InvoChat</CardTitle>
            <CardDescription>The authentication system has been reset. You can now build a new one from scratch.</CardDescription>
        </CardHeader>
        <CardContent>
            <Button asChild className="w-full">
                <Link href="/dashboard">
                    Go to Dashboard
                </Link>
            </Button>
        </CardContent>
      </Card>
    </div>
  );
}
