
'use client';

import React, { useState, useEffect, useRef } from 'react';
import { useFormStatus } from 'react-dom';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { signup } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME, CSRF_COOKIE_NAME, getCookie } from '@/lib/csrf';

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
}

export function SignupForm({ error: initialError }: SignupFormProps) {
    const [error, setError] = useState(initialError);
    const [csrfToken, setCsrfToken] = useState<string | null>(null);
    const formRef = useRef<HTMLFormElement>(null);

    useEffect(() => {
        setCsrfToken(getCookie(CSRF_COOKIE_NAME));
    }, []);
    
    useEffect(() => {
        setError(initialError);
        if (initialError) {
            const url = new URL(window.location.href);
            url.searchParams.delete('error');
            window.history.replaceState({}, '', url.toString());
        }
    }, [initialError]);

    const handleFormAction = async (formData: FormData) => {
        const password = formData.get('password');
        const confirmPassword = formData.get('confirmPassword');

        if (password !== confirmPassword) {
            setError('Passwords do not match.');
            return;
        }
        setError(null);
        await signup(formData);
    };

    const handleInteraction = () => {
        if (error) setError(null);
    };

    return (
        <form ref={formRef} action={handleFormAction} className="grid gap-4" onChange={handleInteraction}>
            {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
            <div className="grid gap-2">
                <Label htmlFor="companyName" className="text-slate-300">Company Name</Label>
                <Input
                    id="companyName"
                    name="companyName"
                    type="text"
                    placeholder="Your Company Inc."
                    required
                    className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
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
                    className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
                />
            </div>
            <div className="grid gap-2">
                <Label htmlFor="password" className="text-slate-300">Password</Label>
                <PasswordInput
                    id="password"
                    name="password"
                    placeholder="••••••••"
                    required
                    minLength={8}
                />
                <p className="text-xs text-slate-400 px-1">
                    Must be at least 8 characters.
                </p>
            </div>
            <div className="grid gap-2">
                <Label htmlFor="confirmPassword" className="text-slate-300">Confirm Password</Label>
                <PasswordInput
                    id="confirmPassword"
                    name="confirmPassword"
                    placeholder="••••••••"
                    required
                    minLength={8}
                />
            </div>
            {error && (
              <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton disabled={!csrfToken} />
        </form>
    );
}
