
'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';

const CSRF_FORM_NAME = 'csrf_token';
const CSRF_COOKIE_NAME = 'csrf_token';


function LoginSubmitButton({ disabled }: { disabled: boolean }) {
    const { pending } = useFormStatus();
    return (
        <Button 
            type="submit" 
            disabled={disabled || pending} 
            className="w-full h-12 text-base font-semibold bg-gradient-to-r from-blue-600 to-purple-600 text-white shadow-lg transition-all duration-300 ease-in-out hover:opacity-90 hover:shadow-xl disabled:opacity-50 rounded-lg"
        >
            {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

interface LoginFormProps {
    error: string | null;
}

export function LoginForm({ error: initialError }: LoginFormProps) {
  const [error, setError] = useState(initialError);
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    setError(initialError);
  }, [initialError]);

  useEffect(() => {
    // Reading the cookie on the client side ensures we get the latest value
    // after the middleware has run.
    const token = document.cookie
      .split('; ')
      .find(row => row.startsWith(`${CSRF_COOKIE_NAME}=`))
      ?.split('=')[1];
    setCsrfToken(token || null);
  }, []);

  const handleInteraction = () => {
    if (error) setError(null);
  };

  return (
    <form action={login} className="space-y-4" onChange={handleInteraction}>
        {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
        <div className="space-y-2">
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
        
        <div className="space-y-2">
            <div className="flex items-center justify-between">
            <Label htmlFor="password" className="text-slate-300">Password</Label>
            <Link
                href="/forgot-password"
                className="text-sm text-blue-400 hover:text-blue-300 transition-colors"
            >
                Forgot password?
            </Link>
            </div>
            <PasswordInput
                id="password"
                name="password"
                placeholder="••••••••"
                required
            />
        </div>
        
        {error && (
            <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                <AlertTriangle className="h-4 w-4 flex-shrink-0" />
                <AlertDescription>{error}</AlertDescription>
            </Alert>
        )}
        
        <div className="pt-2">
            <LoginSubmitButton disabled={!csrfToken} />
        </div>
    </form>
  );
}
