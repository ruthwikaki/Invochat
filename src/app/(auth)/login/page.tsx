
'use client';

import React, { useState } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { Eye, EyeOff, AlertTriangle, Loader2 } from 'lucide-react';

import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { InvoChatLogo } from '@/components/invochat-logo';
import { useCsrfToken } from '@/hooks/use-csrf';
import { CSRFInput } from '@/components/auth/csrf-input';
import { login } from '@/app/(auth)/actions';
import { motion } from 'framer-motion';

function LoginButton() {
  const { pending } = useFormStatus();
  const token = useCsrfToken();
  const isDisabled = pending || !token;

  return (
    <Button
      type="submit"
      disabled={isDisabled}
      className="w-full h-12 text-base font-semibold bg-gradient-to-r from-blue-600 to-purple-600 text-white shadow-lg transition-all duration-300 ease-in-out hover:opacity-90 hover:shadow-xl disabled:opacity-50 rounded-lg flex items-center justify-center"
    >
      {pending ? (
        <Loader2 className="w-5 h-5 animate-spin" />
      ) : (
        'Sign In'
      )}
    </Button>
  );
}

function PasswordInput() {
    const [showPassword, setShowPassword] = useState(false);
    return (
        <div className="relative">
            <Input
              id="password"
              name="password"
              type={showPassword ? 'text' : 'password'}
              placeholder="••••••••"
              className="h-12 flex w-full rounded-lg border bg-slate-800/50 border-slate-600 px-3 py-3 pr-10 text-base text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
              required
            />
            <button
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-white transition-colors p-1"
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

export default function LoginPage({ searchParams }: { searchParams?: { error?: string } }) {
  const cardVariants = {
    hidden: { opacity: 0, y: 20 },
    visible: { opacity: 1, y: 0, transition: { duration: 0.5 } }
  };

  return (
    <div className="relative flex items-center justify-center min-h-screen w-full overflow-hidden bg-slate-900 text-white p-4">
      {/* Animated Background */}
      <div className="absolute inset-0 -z-10">
        <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-purple-900/20 to-slate-900" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))]" />
        <div className="absolute top-0 left-1/4 w-72 h-72 bg-purple-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob" />
        <div className="absolute top-0 right-1/4 w-72 h-72 bg-blue-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-2000" />
        <div className="absolute bottom-1/4 left-1/3 w-72 h-72 bg-pink-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-4000" />
      </div>

      <motion.div 
        variants={cardVariants}
        initial="hidden"
        animate="visible"
        className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <div className="text-center">
            <div className="flex justify-center items-center gap-3 mb-4">
                <InvoChatLogo className="h-10 w-10 text-blue-500" />
                <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">
                  InvoChat
                </h1>
            </div>
            <h2 className="text-xl font-semibold text-slate-200">Welcome to Intelligent Inventory</h2>
            <p className="text-slate-400 mt-2 text-sm">Sign in to access AI-powered insights.</p>
        </div>

        <form action={login} className="space-y-4">
          <CSRFInput />
          <div className="space-y-2">
            <Label htmlFor="email" className="text-sm font-medium text-slate-300">
              Email
            </Label>
            <Input
              id="email"
              name="email"
              type="email"
              placeholder="you@company.com"
              className="h-12 flex w-full rounded-lg border bg-slate-800/50 border-slate-600 px-3 py-3 text-base text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all"
              required
            />
          </div>
          
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label htmlFor="password" className="text-sm font-medium text-slate-300">
                Password
              </Label>
              <Link
                href="/forgot-password"
                className="text-sm text-blue-400 hover:text-blue-300 transition-colors"
              >
                Forgot password?
              </Link>
            </div>
            <PasswordInput />
          </div>
          
          {searchParams?.error && (
            <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
              <AlertTriangle className="h-4 w-4" />
              <AlertDescription>{searchParams.error}</AlertDescription>
            </Alert>
          )}
          
          <div className="pt-2">
            <LoginButton />
          </div>
        </form>

        <div className="text-center text-sm text-slate-400">
          Don't have an account?{' '}
          <Link href="/signup" className="font-semibold text-blue-400 hover:text-blue-300 transition-colors">
            Sign up
          </Link>
        </div>
      </motion.div>
    </div>
  );
}
