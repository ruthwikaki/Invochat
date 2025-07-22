
'use client'; // Error components must be Client Components

import { useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AlertTriangle } from 'lucide-react';
import * as Sentry from '@sentry/nextjs';
import { useAuth } from '@/context/auth-context';

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const { user } = useAuth();

  useEffect(() => {
    // Set user context for Sentry
    if (user) {
      Sentry.setUser({ id: user.id, email: user.email });
    } else {
      Sentry.setUser(null);
    }
    // Log the error to Sentry
    Sentry.captureException(error);
  }, [error, user]);

  const isDev = process.env.NODE_ENV === 'development';

  return (
    <div className="flex items-center justify-center min-h-full p-4">
      <Card className="w-full max-w-md text-center">
        <CardHeader>
          <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
            <AlertTriangle className="h-8 w-8 text-destructive" />
          </div>
          <CardTitle className="mt-4">Oops! Something Went Wrong</CardTitle>
          <CardDescription>
            A part of the application has encountered an unexpected error.
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
  );
}
