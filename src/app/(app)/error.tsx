
'use client'; // Error components must be Client Components

import { useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import { logger } from '@/lib/logger';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log the error to the console
    logger.error('Global Error Boundary Caught:', error);
  }, [error]);

  const isDev = process.env.NODE_ENV === 'development';

  return (
    <div className="flex items-center justify-center min-h-dvh bg-muted/40 p-4">
        <Card className="w-full max-w-md text-center">
            <CardHeader>
                <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
                    <AlertTriangle className="h-8 w-8 text-destructive" />
                </div>
                <CardTitle className="mt-4">Something Went Wrong</CardTitle>
                <CardDescription>
                    We encountered an unexpected error. Please try again.
                </CardDescription>
            </CardHeader>
            <CardContent>
                {isDev && (
                  <p className="text-sm text-muted-foreground bg-muted p-3 rounded-md mb-4 font-mono text-left">
                      Error: {error.message}
                  </p>
                )}
                <Button
                    onClick={
                    // Attempt to recover by trying to re-render the segment
                    () => reset()
                    }
                >
                    Try Again
                </Button>
            </CardContent>
        </Card>
    </div>
  );
}
