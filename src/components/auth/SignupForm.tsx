
'use client';

import React from 'react';
import { useFormState, useFormStatus } from 'react-dom';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { signup } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
      <Button type="submit" className="w-full h-12 text-base" disabled={pending}>
        {pending ? <Loader2 className="animate-spin" /> : 'Create Account'}
      </Button>
    );
}

const initialState = {
  error: undefined,
};

export function SignupForm({ error: initialError }: { error: string | null; }) {
    const [state, formAction] = useFormState(signup, initialState);

    return (
        <form action={formAction} className="grid gap-4">
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
            {(state?.error || initialError) && (
              <Alert variant="destructive">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{state.error || initialError}</AlertDescription>
              </Alert>
            )}
            <div className="pt-2">
                <SubmitButton />
            </div>
        </form>
    );
}
