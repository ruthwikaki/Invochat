'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';
import { CSRF_FORM_NAME, generateAndSetCsrfToken } from '@/lib/csrf-client';

function SubmitButton({ disabled }: { disabled?: boolean }) {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" disabled={disabled || pending}>
            {pending ? <Loader2 className="animate-spin" /> : 'Update Password'}
        </Button>
    );
}

interface UpdatePasswordFormProps {
    error: string | null;
}

export function UpdatePasswordForm({ error: initialError }: UpdatePasswordFormProps) {
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
        startTransition(() => {
            updatePassword(formData);
        });
    }

  return (
    <form action={formAction} className="grid gap-4" onChange={handleInteraction}>
        {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
        <div className="grid gap-2">
          <Label htmlFor="password" className="text-slate-300">New Password</Label>
           <PasswordInput
                id="password"
                name="password"
                required
                placeholder="••••••••"
                autoComplete="new-password"
                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
           />
        </div>
         <div className="grid gap-2">
          <Label htmlFor="confirmPassword" className="text-slate-300">Confirm New Password</Label>
          <PasswordInput
            id="confirmPassword"
            name="confirmPassword"
            placeholder="••••••••"
            required
            className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
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
