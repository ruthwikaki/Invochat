
'use client';

import React, { useState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { requestPasswordReset } from '@/app/(auth)/actions';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';

function getCookie(name: string): string | null {
  if (typeof document === 'undefined') {
    return null;
  }
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) {
    return parts.pop()?.split(';').shift() || null;
  }
  return null;
}

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
}

export function ForgotPasswordForm({ error: initialError }: ForgotPasswordFormProps) {
  const [error, setError] = useState(initialError);
  const [csrfToken, setCsrfToken] = useState<string | null>(null);

  useEffect(() => {
    setCsrfToken(getCookie(CSRF_COOKIE_NAME));
  }, []);
  
  const handleInteraction = () => {
    if (error) setError(null);
  };

  return (
    <form action={requestPasswordReset} className="grid gap-4" onChange={handleInteraction}>
      <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
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
      <Button type="submit" className="w-full" disabled={!csrfToken}>
        <SubmitButtonContent />
      </Button>
    </form>
  );
}

function SubmitButtonContent() {
  const { pending } = useFormStatus();
  return (
    <>
      {pending ? <Loader2 className="animate-spin" /> : 'Send Password Reset Email'}
    </>
  );
}
