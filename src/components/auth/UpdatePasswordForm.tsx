
'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';

const CSRF_FORM_NAME = 'csrf_token';

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" disabled={pending}>
            {pending ? <Loader2 className="animate-spin" /> : 'Update Password'}
        </Button>
    );
}

interface UpdatePasswordFormProps {
    error: string | null;
    csrfToken: string | null;
}

export function UpdatePasswordForm({ error: initialError, csrfToken }: UpdatePasswordFormProps) {
    const [error, setError] = useState(initialError);

    useEffect(() => {
        setError(initialError);
    }, [initialError]);
    
    const handleSubmit = async (formData: FormData) => {
        if (formData.get('password') !== formData.get('confirmPassword')) {
            setError('Passwords do not match.');
            return;
        }
        setError(null);
        await updatePassword(formData);
    }

    const handleInteraction = () => {
        if (error) setError(null);
    };
    
  return (
    <form action={handleSubmit} className="grid gap-4" onChange={handleInteraction}>
        {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
        <div className="grid gap-2">
          <Label htmlFor="password" className="text-slate-300">New Password</Label>
           <PasswordInput
                id="password"
                name="password"
                required
                placeholder="••••••••"
                autoComplete="new-password"
           />
        </div>
         <div className="grid gap-2">
          <Label htmlFor="confirmPassword" className="text-slate-300">Confirm New Password</Label>
          <PasswordInput
            id="confirmPassword"
            name="confirmPassword"
            placeholder="••••••••"
            required
          />
        </div>
        {error && (
          <Alert variant="destructive">
             <AlertTriangle className="h-4 w-4" />
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}
        <SubmitButton />
    </form>
  );
}
