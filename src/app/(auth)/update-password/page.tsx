
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState } from 'react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { InvoChatLogo } from '@/components/invochat-logo';
import { AlertTriangle, Eye, EyeOff, Loader2 } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';
import { CSRFInput } from '@/components/auth/csrf-input';
import { useCsrfToken } from '@/hooks/use-csrf';

function SubmitButton() {
  const { pending } = useFormStatus();
  const token = useCsrfToken();
  const isDisabled = pending || !token;

  return (
    <Button type="submit" className="w-full" disabled={isDisabled}>
      {pending ? <Loader2 className="animate-spin" /> : 'Update Password'}
    </Button>
  );
}

const PasswordInput = React.forwardRef<HTMLInputElement, React.ComponentProps<'input'>>(
  (props, ref) => {
    const [showPassword, setShowPassword] = useState(false);
    return (
      <div className="relative">
        <Input
          ref={ref}
          type={showPassword ? 'text' : 'password'}
          className="pr-10"
          {...props}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-muted-foreground hover:bg-transparent"
          onClick={() => setShowPassword((prev) => !prev)}
          aria-label={showPassword ? 'Hide password' : 'Show password'}
          tabIndex={-1}
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </Button>
      </div>
    );
  }
);
PasswordInput.displayName = 'PasswordInput';


export default function UpdatePasswordPage({ searchParams }: { searchParams?: { error?: string } }) {
    const [error, setError] = useState(searchParams?.error || null);

    const handleSubmit = async (formData: FormData) => {
        if (formData.get('password') !== formData.get('confirmPassword')) {
            setError('Passwords do not match.');
            return;
        }
        setError(null);
        await updatePassword(formData);
    }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <InvoChatLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight text-foreground">ARVO</h1>
      </div>
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Create a New Password</CardTitle>
          <CardDescription>
            Enter a new password for your account below.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form action={handleSubmit} className="grid gap-4">
            <CSRFInput />
            <div className="grid gap-2">
              <Label htmlFor="password">New Password</Label>
               <PasswordInput
                    id="password"
                    name="password"
                    required
                    placeholder="••••••••"
                    autoComplete="new-password"
               />
            </div>
             <div className="grid gap-2">
              <Label htmlFor="confirmPassword">Confirm New Password</Label>
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
        </CardContent>
      </Card>
    </div>
  );
}