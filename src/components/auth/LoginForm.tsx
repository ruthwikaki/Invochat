
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';

function LoginSubmitButton({ isPending, disabled }: { isPending: boolean, disabled: boolean }) {
    const { pending } = useFormStatus();
    const isDisabled = isPending || pending || disabled;
    return (
        <Button 
            type="submit" 
            disabled={isDisabled} 
            className="w-full h-12 text-base font-semibold"
        >
            {isDisabled ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

interface LoginFormProps {
    initialError: string | null;
}

export function LoginForm({ initialError }: LoginFormProps) {
  const [error, setError] = useState(initialError);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

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
  
  const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const formData = new FormData(e.currentTarget);
    if (!csrfToken) {
        setError('A required security token was not found. Please refresh the page and try again.');
        return;
    }
    formData.append(CSRF_FORM_NAME, csrfToken);
    
    setError(null);
    startTransition(async () => {
      const result = await login(formData);
      if (result?.success) {
        router.push('/dashboard');
        router.refresh();
      } else {
        setError(result?.error || 'An unexpected error occurred.');
      }
    });
  };
  
  return (
    <form onSubmit={handleSubmit} className="space-y-4" onChange={handleInteraction}>
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
            <LoginSubmitButton isPending={isPending} disabled={!csrfToken} />
        </div>
    </form>
  );
}
