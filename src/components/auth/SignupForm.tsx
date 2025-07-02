'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { signup } from '@/app/(auth)/actions';
import { CSRF_FORM_NAME } from '@/lib/csrf';
import { PasswordInput } from './PasswordInput';

function SubmitButton({ disabled }: { disabled: boolean }) {
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
    loadingToken: boolean;
}

export function SignupForm({ error: initialError, csrfToken, loadingToken }: SignupFormProps) {
    const [error, setError] = useState(initialError);
    
    useEffect(() => {
        setError(initialError);
    }, [initialError]);
    
    const handleInteraction = () => {
        if (error) setError(null);
    };

    return (
        <form action={signup} className="grid gap-4" onChange={handleInteraction}>
            <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
            <div className="grid gap-2">
                <Label htmlFor="companyName" className="text-slate-300">Company Name</Label>
                <Input
                    id="companyName"
                    name="companyName"
                    type="text"
                    placeholder="Your Company Inc."
                    required
                    className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
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
                    className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
                />
            </div>
            <div className="grid gap-2">
                <Label htmlFor="password" className="text-slate-300">Password</Label>
                <PasswordInput
                    id="password"
                    name="password"
                    placeholder="••••••••"
                    required
                    minLength={6}
                />
            </div>
            {error && (
              <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton disabled={loadingToken || !csrfToken} />
        </form>
    );
}