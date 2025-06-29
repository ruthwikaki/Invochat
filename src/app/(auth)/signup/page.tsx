
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
import { InvoChatLogo } from '@/components/arvo-logo';
import { CheckCircle } from 'lucide-react';
import { signup } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" className="w-full" disabled={pending}>
      {pending ? 'Signing up...' : 'Sign up'}
    </Button>
  );
}


export default function SignupPage({ searchParams }: { searchParams?: { success?: string; error?: string } }) {

  if (searchParams?.success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
         <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
          <InvoChatLogo className="h-10 w-10" />
          <h1>InvoChat</h1>
        </div>
        <Card className="w-full max-w-sm text-center">
            <CardHeader>
                <div className="mx-auto bg-success/10 p-3 rounded-full w-fit">
                    <CheckCircle className="h-8 w-8 text-success" />
                </div>
                <CardTitle className="mt-4">Success!</CardTitle>
                <CardDescription>
                    Please check your email to verify your account, then sign in.
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
          <CardTitle className="text-2xl">Create Account</CardTitle>
          <CardDescription>
            Enter your information to create your InvoChat account
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action={signup} className="grid gap-4">
            <CSRFInput />
            <div className="grid gap-2">
              <Label htmlFor="companyName">Company Name</Label>
              <Input
                id="companyName"
                name="companyName"
                type="text"
                placeholder="Your Company Inc."
                required
              />
            </div>
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
            <div className="grid gap-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                name="password"
                type="password"
                placeholder="••••••••"
                required
                minLength={6}
              />
            </div>
            {searchParams?.error && (
              <Alert variant="destructive">
                <AlertDescription>{searchParams.error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton />
          </form>
          <div className="mt-4 text-center text-sm">
            Already have an account?{' '}
            <Link href="/login" className="underline">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
