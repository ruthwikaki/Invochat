
'use client';

import React, { useState } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { requestPasswordReset } from '@/app/(auth)/actions';
import { CSRF_FORM_NAME } from '@/lib/csrf';

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
      <Button type="submit" className="w-full" disabled={pending}>
        {pending ? <Loader2 className="animate-spin" /> : 'Send Password Reset Email'}
      </Button>
    );
}

interface ForgotPasswordFormProps {
    csrfToken: string;
    error: string | null;
}

export function ForgotPasswordForm({ csrfToken, error: initialError }: ForgotPasswordFormProps) {
  const [error, setError] = useState(initialError);

  const handleInteraction = () => {
    if (error) setError(null);
  };

  return (
    <form action={requestPasswordReset} className="grid gap-4" onChange={handleInteraction}>
      <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />
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
