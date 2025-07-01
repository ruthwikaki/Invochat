
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { Eye, EyeOff, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { InvoChatLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { useToast } from '@/hooks/use-toast';
import { motion } from 'framer-motion';
import { Alert, AlertDescription } from '@/components/ui/alert';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending} className="w-full">
      {pending ? (
        <motion.div
          className="w-5 h-5 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin"
          aria-label="Loading..."
        />
      ) : (
        'Sign In'
      )}
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


export default function LoginPage({ searchParams }: { searchParams?: { error?: string, message?: string } }) {
    const { toast } = useToast();

    // The success message (e.g., after a password update) is a good use case for a toast
    // as it provides cross-page feedback. Login errors are better handled inline.
    useEffect(() => {
         if (searchParams?.message) {
            toast({
                title: 'Success',
                description: searchParams.message,
            });
        }
    }, [searchParams, toast]);

    return (
        <div className="flex min-h-dvh w-full flex-col items-center justify-center bg-muted/40 p-4">
            <motion.div
                initial={{ opacity: 0, y: -20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.5, ease: 'easeOut' }}
                className="w-full max-w-sm"
            >
                <Card>
                    <CardHeader className="text-center">
                        <div className="mx-auto mb-4">
                            <InvoChatLogo className="h-12 w-12 text-primary" />
                        </div>
                        <CardTitle className="text-2xl">Welcome Back</CardTitle>
                        <CardDescription>Sign in to access your dashboard</CardDescription>
                    </CardHeader>
                    <CardContent>
                        <form action={login} className="grid gap-4">
                            <CSRFInput />
                            <div className="grid gap-2">
                                <Label htmlFor="email">Email</Label>
                                <Input
                                    id="email"
                                    name="email"
                                    type="email"
                                    placeholder="you@company.com"
                                    required
                                    autoComplete="email"
                                />
                            </div>
                            <div className="grid gap-2">
                                <div className="flex items-center justify-between">
                                    <Label htmlFor="password">Password</Label>
                                    <Link
                                        href="/forgot-password"
                                        className="text-sm text-primary hover:underline"
                                    >
                                        Forgot password?
                                    </Link>
                                </div>
                                <PasswordInput
                                    id="password"
                                    name="password"
                                    placeholder="••••••••"
                                    required
                                    autoComplete="current-password"
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
                    </CardContent>
                    <CardFooter className="justify-center">
                         <p className="text-sm text-muted-foreground">
                            Don&apos;t have an account?{' '}
                            <Link href="/signup" className="font-semibold text-primary hover:underline">
                                Sign up
                            </Link>
                        </p>
                    </CardFooter>
                </Card>
            </motion.div>
             <div className="mt-6 text-xs text-muted-foreground space-x-4">
                <Link href="/terms" className="hover:underline">Terms of Service</Link>
                <Link href="/privacy" className="hover:underline">Privacy Policy</Link>
            </div>
        </div>
    );
}
