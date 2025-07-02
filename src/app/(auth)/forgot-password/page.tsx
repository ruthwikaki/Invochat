
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
import { Alert, AlertDescription } from '@/components/ui/alert';
import Link from 'next/link';
import { ArvoLogo } from '@/components/arvo-logo';
import { CheckCircle, AlertTriangle, Loader2 } from 'lucide-react';
import { requestPasswordReset } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { motion } from 'framer-motion';
import { useCsrfToken } from '@/hooks/use-csrf';

function SubmitButton() {
  const { pending } = useFormStatus();
  const token = useCsrfToken();
  const isDisabled = pending || !token;

  return (
    <Button type="submit" className="w-full" disabled={isDisabled}>
      {pending ? <Loader2 className="animate-spin" /> : 'Send Password Reset Email'}
    </Button>
  );
}

export default function ForgotPasswordPage({ searchParams }: { searchParams?: { success?: string; error?: string } }) {

  if (searchParams?.success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-4">
        <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
            className="w-full"
        >
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
        </motion.div>
      </div>
    );
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <ArvoLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight text-foreground">ARVO</h1>
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
            <Link href="/login" className="underline text-primary">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
