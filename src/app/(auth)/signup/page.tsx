
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
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
import { CheckCircle, Eye, EyeOff, Loader2, AlertTriangle } from 'lucide-react';
import { signup } from '@/app/(auth)/actions';
import { motion } from 'framer-motion';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';


// Define helper components OUTSIDE the main page component
function SubmitButton({ csrfToken }: { csrfToken: string | null }) {
    const { pending } = useFormStatus();
    const isDisabled = pending || !csrfToken;

    return (
      <Button type="submit" className="w-full h-12 text-base" disabled={isDisabled}>
        {pending ? <Loader2 className="animate-spin" /> : 'Create Account'}
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
          className="pr-10 bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
          {...props}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-slate-400 hover:bg-transparent hover:text-white"
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
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    const cookieValue = document.cookie
      .split('; ')
      .find(row => row.startsWith(`${CSRF_COOKIE_NAME}=`))
      ?.split('=')[1];
    setCsrfToken(cookieValue || null);
  }, []);


  if (searchParams?.success) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-slate-900 p-4">
         <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
          <InvoChatLogo className="h-10 w-10 text-primary" />
           <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">InvoChat</h1>
        </div>
        <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
            className="w-full"
        >
            <Card className="w-full max-w-sm text-center mx-auto bg-slate-800/80 border-slate-700/50 text-white">
                <CardHeader>
                    <div className="mx-auto bg-success/10 p-3 rounded-full w-fit">
                        <CheckCircle className="h-8 w-8 text-green-400" />
                    </div>
                    <CardTitle className="mt-4 text-slate-200">Success!</CardTitle>
                    <CardDescription className="text-slate-400">
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
    <div className="flex min-h-dvh flex-col items-center justify-center bg-slate-900 text-white p-4">
       <div className="absolute inset-0 -z-10">
            <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-purple-900/20 to-slate-900" />
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))]" />
            <div className="absolute top-0 left-1/4 w-72 h-72 bg-purple-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob" />
            <div className="absolute top-0 right-1/4 w-72 h-72 bg-blue-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-2000" />
            <div className="absolute bottom-1/4 left-1/3 w-72 h-72 bg-pink-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-4000" />
        </div>
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <InvoChatLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">InvoChat</h1>
      </div>
      <Card className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <CardHeader className="p-0 text-center">
          <CardTitle className="text-2xl text-slate-200">Create Your Account</CardTitle>
          <CardDescription className="text-slate-400">
            Get started with AI-powered inventory intelligence.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <form action={signup} className="grid gap-4">
            <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
            <div className="grid gap-2">
              <Label htmlFor="companyName" className="text-slate-300">Company Name</Label>
              <Input
                id="companyName"
                name="companyName"
                type="text"
                placeholder="Your Company Inc."
                required
                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="email" className="text-slate-300">Email</Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="password" className="text-slate-300">Password</Label>
              <PasswordInput
                id="password"
                name="password"
                placeholder="••••••••"
                required
                minLength={6}
              />
            </div>
            {searchParams?.error && (
              <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{searchParams.error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton csrfToken={csrfToken} />
          </form>
          <div className="mt-4 text-center text-sm text-slate-400">
            Already have an account?{' '}
            <Link href="/login" className="underline text-blue-400">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
