
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { Eye, EyeOff, AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { InvoChatLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { useToast } from '@/hooks/use-toast';
import { motion, useAnimationControls } from 'framer-motion';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { cn } from '@/lib/utils';
import { useCsrfToken } from '@/hooks/use-csrf';

function SubmitButton() {
  const { pending } = useFormStatus();
  const token = useCsrfToken();
  const isDisabled = pending || !token;

  return (
    <Button
      type="submit"
      disabled={isDisabled}
      className="w-full h-12 text-base font-semibold bg-gradient-to-r from-primary to-cyan-400 text-white shadow-lg transition-all duration-300 ease-in-out hover:opacity-90 hover:shadow-xl disabled:opacity-50"
    >
      {isDisabled ? (
        <motion.div
          className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"
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
          className="pr-10 bg-slate-800/50 border-slate-700 h-12 text-base focus-visible:ring-cyan-500"
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
    const controls = useAnimationControls();

    useEffect(() => {
        // This ensures the intro animation runs, and then the shake animation runs if there's an error.
        const sequence = async () => {
            await controls.start("visible");
            if (searchParams?.error) {
                await controls.start("shake");
            }
        };
        sequence();
    }, [searchParams, controls]);

    useEffect(() => {
         if (searchParams?.message) {
            toast({
                title: 'Success',
                description: searchParams.message,
            });
        }
    }, [searchParams, toast]);

    const cardVariants = {
        hidden: { opacity: 0, y: 50, scale: 0.95 },
        visible: { 
            opacity: 1, 
            y: 0, 
            scale: 1,
            transition: { duration: 0.5, ease: 'easeOut' } 
        },
        shake: {
            x: [0, -10, 10, -10, 10, 0],
            transition: { duration: 0.5 }
        }
    };

    return (
      <div className="relative flex items-center justify-center min-h-dvh w-full overflow-hidden bg-[#020617] text-white">
        {/* Animated Background */}
        <div className="absolute inset-0 -z-10">
          <div className="absolute inset-0 bg-[radial-gradient(circle_500px_at_50%_200px,#3b82f633,transparent)]" />
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))] animate-background-pan" />
        </div>

        <motion.div
            variants={cardVariants}
            initial="hidden"
            animate={controls}
            className={cn(
                "w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl",
                "bg-slate-900/50 backdrop-blur-lg border border-slate-700"
            )}
        >
            <div className="text-center">
                <div className="flex justify-center items-center gap-3 mb-4">
                    <InvoChatLogo className="h-10 w-10 text-primary" />
                    <h1 className="text-4xl font-bold tracking-tighter">InvoChat</h1>
                </div>
                <h2 className="text-2xl font-semibold">AI-Powered Insights Await</h2>
                <p className="text-slate-400 mt-2">Sign in to transform your warehouse with intelligent automation.</p>
            </div>

            <form action={login} className="space-y-4">
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
                        className="bg-slate-800/50 border-slate-700 h-12 text-base focus-visible:ring-cyan-500"
                    />
                </div>
                <div className="space-y-2">
                    <div className="flex items-center justify-between">
                        <Label htmlFor="password" className="text-slate-300">Password</Label>
                        <Link
                            href="/forgot-password"
                            className="text-sm text-cyan-400 hover:underline"
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
                    <Alert variant="destructive" className="bg-destructive/10 border-destructive/30 text-destructive-foreground">
                        <AlertTriangle className="h-4 w-4" />
                        <AlertDescription>{searchParams.error}</AlertDescription>
                    </Alert>
                )}
                
                <div className="pt-2">
                    <SubmitButton />
                </div>
            </form>

            <div className="text-center text-sm text-slate-400">
                Don&apos;t have an account?{' '}
                <Link href="/signup" className="font-semibold text-cyan-400 hover:underline">
                    Sign up
                </Link>
            </div>
        </motion.div>
    </div>
    );
}
