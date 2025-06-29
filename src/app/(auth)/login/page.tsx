
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { Eye, EyeOff, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { ArvoLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <Button
      type="submit"
      disabled={pending}
      className="w-full"
    >
      {pending ? 'Signing in...' : 'Sign In'}
    </Button>
  );
}

const PasswordInput = ({ id, name, required }: { id: string, name: string, required?: boolean }) => {
  const [showPassword, setShowPassword] = useState(false);
  return (
    <div className="relative">
      <Input
        id={id}
        name={name}
        type={showPassword ? 'text' : 'password'}
        placeholder="••••••••"
        required={required}
        className="pr-10"
        autoComplete="current-password"
      />
      <Button
        type="button"
        variant="ghost"
        size="icon"
        className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-muted-foreground hover:bg-transparent"
        onClick={() => setShowPassword(prev => !prev)}
        aria-label={showPassword ? 'Hide password' : 'Show password'}
        tabIndex={-1}
      >
        {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </Button>
    </div>
  );
};

export default function LoginPage({ searchParams }: { searchParams?: { error?: string, message?: string } }) {
  return (
    <div className="w-full lg:grid lg:min-h-dvh lg:grid-cols-2 xl:min-h-dvh">
      <div className="flex items-center justify-center py-12">
        <div className="mx-auto grid w-[350px] gap-6">
          <div className="grid gap-2 text-center">
             <Link href="/" className="mb-4 flex items-center justify-center gap-3 text-2xl font-bold">
                  <ArvoLogo className="h-8 w-8" />
                  <h1 className="text-foreground">ARVO</h1>
              </Link>
            <p className="text-balance text-muted-foreground">
              Enter your email below to login to your account
            </p>
          </div>
          <form action={login} className="grid gap-4">
            {searchParams?.error && (
              <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4" />
                <AlertTitle>Login Failed</AlertTitle>
                <AlertDescription>{searchParams.error}</AlertDescription>
              </Alert>
            )}
             {searchParams?.message && (
              <Alert>
                <AlertTitle>Success</AlertTitle>
                <AlertDescription>{searchParams.message}</AlertDescription>
              </Alert>
            )}
            <div className="grid gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="m@example.com"
                required
                autoComplete="email"
              />
            </div>
            <div className="grid gap-2">
              <div className="flex items-center">
                <Label htmlFor="password">Password</Label>
                <Link
                  href="/forgot-password"
                  className="ml-auto inline-block text-sm underline"
                >
                  Forgot your password?
                </Link>
              </div>
              <PasswordInput id="password" name="password" required />
            </div>
            <SubmitButton />
          </form>
          <div className="mt-4 text-center text-sm">
            Don&apos;t have an account?{" "}
            <Link href="/signup" className="underline">
              Sign up
            </Link>
          </div>
        </div>
      </div>
      <div className="hidden bg-muted lg:block">
        <Image
          src="https://placehold.co/1080x1920.png"
          alt="Warehouse logistics"
          width="1920"
          height="1080"
          className="h-full w-full object-cover dark:brightness-[0.2] dark:grayscale"
          data-ai-hint="warehouse logistics"
        />
      </div>
    </div>
  );
}
