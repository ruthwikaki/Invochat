'use client'; // Error components must be Client Components

import { useEffect } from 'react';
import * as Sentry from '@sentry/nextjs';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  const isDev = process.env.NODE_ENV === 'development';

  return (
    <html>
      <body>
        <div className="flex items-center justify-center min-h-dvh bg-muted/40 p-4">
            <Card className="w-full max-w-md text-center">
                <CardHeader>
                    <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
                        <AlertTriangle className="h-8 w-8 text-destructive" />
                    </div>
                    <CardTitle className="mt-4">Something Went Wrong</CardTitle>
                    <CardDescription>
                        An unexpected error occurred in the application.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    {isDev && (
                      <p className="text-sm text-muted-foreground bg-muted p-3 rounded-md mb-4 font-mono text-left max-h-40 overflow-auto">
                          <strong>Development only:</strong> This will not be shown in production. <br/>
                          Error: {error.message}
                      </p>
                    )}
                    <Button onClick={() => { reset(); }}>Try Again</Button>
                </CardContent>
            </Card>
        </div>
      </body>
    </html>
  );
}
