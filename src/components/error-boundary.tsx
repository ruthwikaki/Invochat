
'use client';

import React, { Component, ErrorInfo, ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AlertTriangle, LogIn } from 'lucide-react';
import { logger } from '@/lib/logger';
import * as Sentry from '@sentry/nextjs';

interface Props {
  children: ReactNode;
  onReset: () => void;
}

interface State {
  hasError: boolean;
  error: Error | null;
}

// A specific component for the session expired error state
function SessionExpiredError() {
  return (
     <div className="flex items-center justify-center h-full p-4">
        <Card className="w-full max-w-md text-center">
            <CardHeader>
                <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit">
                    <LogIn className="h-8 w-8 text-destructive" />
                </div>
                <CardTitle className="mt-4">Session Expired</CardTitle>
                <CardDescription>
                    Your session has expired. Please sign in again to continue.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <Button asChild>
                    <a href="/login">Sign In</a>
                </Button>
            </CardContent>
        </Card>
    </div>
  )
}


class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    logger.error('React Error Boundary Caught:', { error: error.message, componentStack: errorInfo.componentStack });
    Sentry.captureException(error, { extra: { componentStack: errorInfo.componentStack } });
  }

  public render() {
    if (this.state.hasError) {
      const isDev = process.env.NODE_ENV === 'development';
      const errorMessage = this.state.error?.message || '';
      
      // Specifically check for authentication errors.
      if (errorMessage.includes("Authentication required") || errorMessage.includes("Authorization failed")) {
          return <SessionExpiredError />;
      }
      
      return (
        <div className="flex items-center justify-center h-full p-4">
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
                    {isDev && errorMessage && (
                        <p className="text-sm text-muted-foreground bg-muted p-3 rounded-md mb-4 font-mono text-left max-h-40 overflow-auto">
                           Error: {errorMessage}
                        </p>
                    )}
                    <Button onClick={this.props.onReset}>
                        Try Again
                    </Button>
                </CardContent>
            </Card>
        </div>
      );
    }

    return this.props.children;
  }
}

export default ErrorBoundary;
