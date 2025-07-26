
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';

function LoginSubmitButton({ disabled }: { disabled?: boolean }) {
    const { pending } = useFormStatus();
    return (
        <Button 
            type="submit" 
            disabled={disabled || pending} 
            className="w-full h-12 text-base font-semibold"
        >
            {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

interface LoginFormProps {
    initialError: string | null;
}

export function LoginForm({ initialError }: LoginFormProps) {
  const [error, setError] = useState(initialError);
  const [csrfToken, setCsrfToken] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    generateAndSetCsrfToken(setCsrfToken);
  }, []);

  useEffect(() => {
    setError(initialError);
    if (initialError) {
        const url = new URL(window.location.href);
        url.searchParams.delete('error');
        window.history.replaceState({}, '', url.toString());
    }
  }, [initialError]);

  const handleInteraction = () => {
    if (error) setError(null);
  };
  
  const formAction = (formData: FormData) => {
      startTransition(async () => {
          await login(formData);
      });
  }

  return (
    <form action={formAction} className="space-y-4" onChange={handleInteraction}>
        {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
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
            <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4 flex-shrink-0" />
                <AlertDescription>{error}</AlertDescription>
            </Alert>
        )}
        
        <div className="pt-2">
            <LoginSubmitButton disabled={!csrfToken || isPending} />
        </div>
    </form>
  );
}
