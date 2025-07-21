'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { AlertTriangle, CheckCircle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME } from '@/lib/csrf';

function LoginSubmitButton({ disabled }: { disabled?: boolean }) {
    const { pending } = useFormStatus();
    return (
        <Button 
            type="submit" 
            disabled={disabled || pending} 
            className="w-full h-12 text-base font-semibold bg-primary text-primary-foreground shadow-lg transition-all duration-300 ease-in-out hover:bg-primary/90 hover:shadow-xl disabled:opacity-50 rounded-lg"
        >
            {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

interface LoginFormProps {
    error: string | null;
    message: string | null;
    csrfToken: string;
}

export function LoginForm({ error: initialError, message: initialMessage, csrfToken }: LoginFormProps) {
  const [error, setError] = useState(initialError);
  const [message, setMessage] = useState(initialMessage);

  useEffect(() => {
    setError(initialError);
    setMessage(initialMessage);
    if (initialError || initialMessage) {
        // Clear the error from the URL without reloading the page
        const url = new URL(window.location.href);
        url.searchParams.delete('error');
        url.searchParams.delete('message');
        window.history.replaceState({}, '', url.toString());
    }
  }, [initialError, initialMessage]);

  const handleInteraction = () => {
    if (error) setError(null);
    if (message) setMessage(null);
  };

  return (
    <form action={login} className="space-y-4" onChange={handleInteraction}>
        <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />
        <div className="space-y-2">
            <Label htmlFor="email" className="text-slate-300">Email</Label>
            <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
            />
        </div>
        
        <div className="space-y-2">
            <div className="flex items-center justify-between">
            <Label htmlFor="password" className="text-slate-300">Password</Label>
            <Link
                href="/forgot-password"
                className="text-sm text-primary/80 hover:text-primary transition-colors"
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

        {message && (
            <Alert className="bg-green-500/10 border-green-500/30 text-green-400">
                <CheckCircle className="h-4 w-4 flex-shrink-0" />
                <AlertDescription>{message}</AlertDescription>
            </Alert>
        )}
        
        <div className="pt-2">
            <LoginSubmitButton disabled={!csrfToken} />
        </div>
    </form>
  );
}
