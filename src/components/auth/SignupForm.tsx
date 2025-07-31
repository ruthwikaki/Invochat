
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { useRouter } from 'next/navigation';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { signup } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';

function SubmitButton({ isPending, disabled }: { isPending: boolean, disabled: boolean }) {
    const { pending } = useFormStatus();
    const isDisabled = isPending || pending || disabled;
    return (
      <Button type="submit" className="w-full h-12 text-base" disabled={isDisabled}>
        {isDisabled ? <Loader2 className="animate-spin" /> : 'Create Account'}
      </Button>
    );
}

interface SignupFormProps {
    error: string | null;
}

export function SignupForm({ error: initialError }: SignupFormProps) {
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

    const handleSubmit = (formData: FormData) => {
      if (!csrfToken) {
        setError('A required security token was not found. Please refresh the page and try again.');
        return;
      }
      formData.append(CSRF_FORM_NAME, csrfToken);

      setError(null);
      startTransition(async () => {
        const result = await signup(formData);
        if (result.success) {
          if (result.message) {
            router.push(`/login?message=${encodeURIComponent(result.message)}`);
          } else {
            // A direct sign up without email confirmation will land here
            router.push('/dashboard');
          }
          router.refresh(); // Important to update the auth state for the layout
        } else {
          setError(result.error || 'An unexpected error occurred.');
        }
      });
    };

    return (
        <form action={handleSubmit} className="grid gap-4" onChange={handleInteraction}>
            <div className="grid gap-2">
                <Label htmlFor="companyName">Company Name</Label>
                <Input
                    id="companyName"
                    name="companyName"
                    type="text"
                    placeholder="Your Company Inc."
                    required
                />
            </div>
            <div className="grid gap-2">
                <Label htmlFor="email">Email</Label>
                <Input
                    id="email"
                    name="email"
                    type="email"
                    placeholder="you@company.com"
                    required
                />
            </div>
            <div className="grid gap-2">
                <Label htmlFor="password">Password</Label>
                <PasswordInput
                    id="password"
                    name="password"
                    placeholder="••••••••"
                    required
                    minLength={8}
                />
                <p className="text-xs text-muted-foreground px-1">
                    Must be at least 8 characters.
                </p>
            </div>
            <div className="grid gap-2">
                <Label htmlFor="confirmPassword">Confirm Password</Label>
                <PasswordInput
                    id="confirmPassword"
                    name="confirmPassword"
                    placeholder="••••••••"
                    required
                    minLength={8}
                />
            </div>
            {error && (
              <Alert variant="destructive">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <div className="pt-2">
                <SubmitButton isPending={isPending} disabled={!csrfToken} />
            </div>
        </form>
    );
}
