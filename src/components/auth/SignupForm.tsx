
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { signup } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME } from '@/lib/csrf-client';

function SubmitButton({ disabled }: { disabled?: boolean }) {
    const { pending } = useFormStatus();
    return (
      <Button type="submit" className="w-full h-12 text-base" disabled={disabled || pending}>
        {pending ? <Loader2 className="animate-spin" /> : 'Create Account'}
      </Button>
    );
}

interface SignupFormProps {
    error: string | null;
    csrfToken: string | null;
}

export function SignupForm({ error: initialError, csrfToken }: SignupFormProps) {
    const [error, setError] = useState(initialError);
    const [isPending, startTransition] = useTransition();

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
        startTransition(() => {
            signup(formData);
        });
    }

    return (
        <form action={formAction} className="grid gap-4" onChange={handleInteraction}>
            {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
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
            <SubmitButton disabled={!csrfToken || isPending} />
        </form>
    );
}
