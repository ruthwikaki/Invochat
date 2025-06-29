
'use client';

import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import Link from 'next/link';
import { InvoChatLogo } from '@/components/arvo-logo';
import { CheckCircle, AlertTriangle } from 'lucide-react';
import { requestPasswordReset } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" className="w-full" disabled={pending}>
      {pending ? 'Sending...' : 'Send Password Reset Email'}
    </Button>
  );
}

export default function ForgotPasswordPage({ searchParams }: { searchParams?: { success?: string; error?: string } }) {

  if (searchParams?.success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-sm text-center">
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
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <InvoChatLogo className="h-10 w-10" />
        <h1>InvoChat</h1>
      </div>
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Forgot Password</CardTitle>
          <CardDescription>
            Enter your email and we'll send you a link to reset your password.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action={requestPasswordReset} className="grid gap-4">
            <CSRFInput />
            <div className="grid gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
              />
            </div>
            {searchParams?.error && (
              <Alert variant="destructive">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{searchParams.error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton />
          </form>
          <div className="mt-4 text-center text-sm">
            Remembered your password?{' '}
            <Link href="/login" className="underline">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
