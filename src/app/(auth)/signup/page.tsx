
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState } from 'react';
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
import { InvoChatLogo } from '@/components/invochat-logo';
import { CheckCircle, Eye, EyeOff } from 'lucide-react';
import { signup } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { motion } from 'framer-motion';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" className="w-full" disabled={pending}>
      {pending ? 'Signing up...' : 'Sign up'}
    </Button>
  );
}

const PasswordInput = React.forwardRef<HTMLInputElement, React.ComponentProps<'input'>>(
  (props, ref) => {
    const [showPassword, setShowPassword] = useState(false);
    return (
      <div className="relative">
        <Input
          ref={ref}
          type={showPassword ? 'text' : 'password'}
          className="pr-10"
          {...props}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-muted-foreground hover:bg-transparent"
          onClick={() => setShowPassword((prev) => !prev)}
          aria-label={showPassword ? 'Hide password' : 'Show password'}
          tabIndex={-1}
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </Button>
      </div>
    );
  }
);
PasswordInput.displayName = 'PasswordInput';


export default function SignupPage({ searchParams }: { searchParams?: { success?: string; error?: string } }) {

  if (searchParams?.success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
         <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
          <InvoChatLogo className="h-10 w-10" />
          <h1>InvoChat</h1>
        </div>
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
        </motion.div>
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
              <PasswordInput
                id="password"
                name="password"
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

    