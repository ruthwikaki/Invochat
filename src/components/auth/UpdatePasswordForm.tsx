
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';

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
}

export function UpdatePasswordForm({ error: initialError }: UpdatePasswordFormProps) {
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
        startTransition(async () => {
            await updatePassword(null, formData);
        });
    }

  return (
    <form action={formAction} className="grid gap-4" onChange={handleInteraction}>
        <div className="grid gap-2">
          <Label htmlFor="password">New Password</Label>
           <PasswordInput
                id="password"
                name="password"
                required
                placeholder="••••••••"
                autoComplete="new-password"
                className="bg-muted/50"
           />
        </div>
         <div className="grid gap-2">
          <Label htmlFor="confirmPassword">Confirm New Password</Label>
          <PasswordInput
            id="confirmPassword"
            name="confirmPassword"
            placeholder="••••••••"
            required
            className="bg-muted/50"
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


