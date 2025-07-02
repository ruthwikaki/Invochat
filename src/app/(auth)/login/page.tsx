
'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { Eye, EyeOff, AlertTriangle, Loader2 } from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { ArvoLogo } from '@/components/arvo-logo';
import { useCsrfToken } from '@/hooks/use-csrf';
import { CSRFInput } from '@/components/auth/csrf-input';
import { login } from '@/app/(auth)/actions';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

function PasswordInput() {
    const [showPassword, setShowPassword] = useState(false);
    return (
        <div className="relative">
            <Input
              id="password"
              name="password"
              type={showPassword ? 'text' : 'password'}
              placeholder="••••••••"
              required
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors p-1"
              aria-label={showPassword ? "Hide password" : "Show password"}
            >
              {showPassword ? (
                <EyeOff className="h-5 w-5" />
              ) : (
                <Eye className="h-5 w-5" />
              )}
            </button>
        </div>
    );
}

function SubmitButton() {
    const { pending } = useFormStatus();
    const token = useCsrfToken();
    const isDisabled = pending || !token;

    return (
        <Button type="submit" disabled={isDisabled} className="w-full">
            {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

export default function LoginPage({ searchParams }: { searchParams?: { error?: string, message?: string } }) {

  return (
    <div className="flex items-center justify-center min-h-dvh w-full bg-background/95 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
            <div className="flex justify-center items-center gap-3 mb-4">
                <ArvoLogo className="h-10 w-10 text-primary" />
                <h1 className="text-4xl font-bold tracking-tight text-foreground">
                  ARVO
                </h1>
            </div>
            <CardTitle className="text-2xl">Welcome Back</CardTitle>
            <CardDescription>Sign in to access your intelligent inventory assistant.</CardDescription>
        </CardHeader>
        <CardContent>
            <form action={login} className="space-y-4">
            <CSRFInput />
            <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
                />
            </div>
            
            <div className="space-y-2">
                <div className="flex items-center justify-between">
                <Label htmlFor="password">Password</Label>
                <Link
                    href="/forgot-password"
                    className="text-sm text-primary hover:underline"
                >
                    Forgot password?
                </Link>
                </div>
                <PasswordInput />
            </div>
            
            {searchParams?.error && (
                <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{searchParams.error}</AlertDescription>
                </Alert>
            )}

            {searchParams?.message && (
                <Alert>
                <AlertDescription>{searchParams.message}</AlertDescription>
                </Alert>
            )}
            
            <div className="pt-2">
                <SubmitButton />
            </div>
            </form>

            <div className="mt-4 text-center text-sm">
            Don&apos;t have an account?{' '}
            <Link href="/signup" className="font-semibold text-primary hover:underline">
                Sign up
            </Link>
            </div>
        </CardContent>
      </Card>
    </div>
  );
}
