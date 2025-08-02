
'use client';

import React, { useState, useEffect, useTransition } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { requestPasswordReset } from '@/app/(auth)/actions';

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? <Loader2 className="animate-spin" /> : 'Send Password Reset Email'}
      </Button>
    );
}

interface ForgotPasswordFormProps {
    error: string | null;
    success: boolean;
}

export function ForgotPasswordForm({ error: initialError, success: initialSuccess }: ForgotPasswordFormProps) {
  const [error, setError] = useState(initialError);
  const [success, setSuccess] = useState(initialSuccess);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    setError(initialError);
    if (initialError) {
        const url = new URL(window.location.href);
        url.searchParams.delete('error');
        window.history.replaceState({}, '', url.toString());
    }
  }, [initialError]);
  
    useEffect(() => {
    setSuccess(initialSuccess);
    if (initialSuccess) {
        const url = new URL(window.location.href);
        url.searchParams.delete('success');
        window.history.replaceState({}, '', url.toString());
    }
  }, [initialSuccess]);


  const handleInteraction = () => {
    if (error) setError(null);
    if (success) setSuccess(false);
  };
  
  const formAction = (formData: FormData) => {
    startTransition(async () => {
        await requestPasswordReset(formData);
    })
  }

  return (
    <form action={formAction} className="grid gap-4" onChange={handleInteraction}>
      <div className="grid gap-2">
        <Label htmlFor="email">Email</Label>
        <Input
          id="email"
          name="email"
          type="email"
          placeholder="you@company.com"
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
       {success && (
        <Alert variant="default" className="bg-success/10 border-success/20 text-success-foreground">
          <AlertDescription>If an account exists for that email, a password reset link has been sent.</AlertDescription>
        </Alert>
      )}
      <SubmitButton />
    </form>
  );
}
