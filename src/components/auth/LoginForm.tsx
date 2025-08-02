
'use client';

import React from 'react';
import { useFormState, useFormStatus } from 'react-dom';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { login } from '@/app/(auth)/actions';
import { PasswordInput } from './PasswordInput';

function LoginSubmitButton() {
    const { pending } = useFormStatus();
    return (
        <Button 
            type="submit" 
            disabled={pending} 
            className="w-full h-12 text-base font-semibold"
        >
            {pending ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
        </Button>
    )
}

const initialState = {
    error: null,
    success: false,
};

export function LoginForm({ initialError }: { initialError: string | null; }) {
  const [state, formAction] = useFormState(login, initialState);
  const router = useRouter();

  React.useEffect(() => {
    if (state.success) {
      router.push('/dashboard');
      router.refresh();
    }
  }, [state.success, router]);

  return (
    <form action={formAction} className="space-y-4">
        <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
            />
        </div>
        
        <div className="space-y-2">
            <div className="flex items-center justify-between">
            <Label htmlFor="password">Password</Label>
            <Link
                href="/forgot-password"
                className="text-sm text-primary/80 hover:text-primary transition-colors"
            >
                Forgot password?
            </Link>
            </div>
            <PasswordInput
                id="password"
                name="password"
                placeholder="••••••••"
                required
            />
        </div>
        
        {(state?.error || initialError) && (
            <Alert variant="destructive">
                <AlertTriangle className="h-4 w-4 flex-shrink-0" />
                <AlertDescription>{state?.error || initialError}</AlertDescription>
            </Alert>
        )}
        
        <div className="pt-2">
            <LoginSubmitButton />
        </div>
    </form>
  );
}
