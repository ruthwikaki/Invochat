'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { motion, AnimatePresence } from 'framer-motion';
import { Eye, EyeOff, AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { InvoChatLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { useToast } from '@/hooks/use-toast';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { useCsrfToken } from '@/hooks/use-csrf';

function SubmitButton() {
  const { pending } = useFormStatus();
  const token = useCsrfToken();
  const isDisabled = pending || !token;

  return (
    <Button
      type="submit"
      disabled={isDisabled}
      className="w-full h-12 text-base font-semibold bg-gradient-to-r from-primary to-accent text-primary-foreground shadow-lg transition-all duration-300 ease-in-out hover:opacity-90 hover:shadow-xl disabled:opacity-50"
    >
      {pending ? (
        <Loader2 className="w-5 h-5 animate-spin" aria-label="Loading..." />
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
          className="pr-10 bg-slate-800/50 border-slate-700 h-12 text-base focus:ring-accent"
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
    const [errorKey, setErrorKey] = useState(Date.now());

    useEffect(() => {
        if (searchParams?.message) {
            toast({
                title: 'Success',
                description: searchParams.message,
            });
        }
        if(searchParams?.error) {
            setErrorKey(Date.now()); // Re-trigger animation on new error
        }
    }, [searchParams, toast]);

    return (
      <div className="relative flex items-center justify-center min-h-dvh w-full overflow-hidden bg-slate-900 text-white p-4">
        {/* Animated Background */}
        <div className="absolute inset-0 -z-10 bg-gradient-to-br from-slate-900 via-purple-900/10 to-background" />
         <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))]" />


        <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5, ease: 'easeOut' }}
            className="w-full max-w-sm p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-900/50 backdrop-blur-lg border border-slate-700/50"
        >
            <div className="text-center">
                <div className="flex justify-center items-center gap-3 mb-4">
                    <InvoChatLogo className="h-10 w-10 text-primary" />
                    <h1 className="text-4xl font-bold tracking-tighter">InvoChat</h1>
                </div>
                <h2 className="text-xl font-semibold text-slate-200">Welcome to Intelligent Inventory</h2>
                <p className="text-slate-400 mt-2 text-sm">Sign in to access AI-powered insights.</p>
            </div>

            <form
                action={login}
                className="space-y-4"
            >
                <CSRFInput />
                <div className="space-y-2">
                    <Label htmlFor="email" className="text-slate-300">Email</Label>
                    <Input
                        id="email"
                        name="email"
                        type="email"
                        placeholder="you@company.com"
                        required
                        autoComplete="email"
                        className="bg-slate-800/50 border-slate-700 h-12 text-base focus:ring-accent"
                    />
                </div>
                <div className="space-y-2">
                    <div className="flex items-center justify-between">
                        <Label htmlFor="password" className="text-slate-300">Password</Label>
                        <Link
                            href="/forgot-password"
                            className="text-sm text-accent hover:underline"
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
                
                <AnimatePresence>
                {searchParams?.error && (
                    <motion.div
                        key={errorKey}
                        initial={{ opacity: 0, y: -10 }}
                        animate={{ opacity: 1, y: 0, x: [-5, 5, -5, 5, 0] }}
                        exit={{ opacity: 0, y: 10 }}
                        transition={{ duration: 0.4, type: 'spring' }}
                    >
                        <Alert variant="destructive" className="bg-destructive/10 border-destructive/30 text-destructive-foreground">
                            <AlertTriangle className="h-4 w-4" />
                            <AlertDescription>{searchParams.error}</AlertDescription>
                        </Alert>
                    </motion.div>
                )}
                </AnimatePresence>
                
                <div className="pt-2">
                    <SubmitButton />
                </div>
            </form>

            <div className="text-center text-sm text-slate-400">
                Don't have an account?{' '}
                <Link href="/signup" className="font-semibold text-accent hover:underline">
                    Sign up
                </Link>
            </div>
        </motion.div>
    </div>
    );
}
