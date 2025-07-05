
'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { CheckCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ForgotPasswordForm } from '@/components/auth/ForgotPasswordForm';
import { getCookie } from '@/lib/csrf';

export default function ForgotPasswordPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
  const success = searchParams?.success === 'true';
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    setCsrfToken(getCookie('csrf_token'));
  }, []);
  
  if (success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-4">
        <Card className="w-full max-w-sm text-center mx-auto">
          <CardHeader>
              <div className="mx-auto bg-success/10 p-3 rounded-full w-fit">
                  <CheckCircle className="h-8 w-8 text-success" />
              </div>
              <CardTitle className="mt-4">Check Your Email</CardTitle>
              <CardDescription>
                  If an account with that email exists, we've sent a link to reset your password.
              </CardDescription>
          </CardHeader>
          <CardContent>
              <Button asChild className="w-full">
                  <Link href="/login">Back to Sign In</Link>
              </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-slate-900 text-white p-4">
        <div className="absolute inset-0 -z-10">
            <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-purple-900/20 to-slate-900" />
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))]" />
        </div>
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold">
        <InvoChatLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">InvoChat</h1>
      </div>
      <Card className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <CardHeader className="p-0 text-center">
          <CardTitle className="text-2xl text-slate-200">Forgot Password</CardTitle>
          <CardDescription className="text-slate-400">
            Enter your email and we'll send you a link to reset your password.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <ForgotPasswordForm 
            error={error}
            csrfToken={csrfToken}
          />
          <div className="mt-4 text-center text-sm text-slate-400">
            Remembered your password?{' '}
            <Link href="/login" className="underline text-blue-400">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
