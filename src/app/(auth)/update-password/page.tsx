
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
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { InvochatLogo } from '@/components/invochat-logo';
import { AlertTriangle, Eye, EyeOff } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" className="w-full" disabled={pending}>
      {pending ? 'Updating...' : 'Update Password'}
    </Button>
  );
}

const PasswordInput = ({ id, name, required }: { id: string, name: string, required?: boolean }) => {
    const [showPassword, setShowPassword] = useState(false);
    return (
      <div className="relative">
        <Input
          id={id}
          name={name}
          type={showPassword ? 'text' : 'password'}
          placeholder="••••••••"
          required={required}
          className="pr-10"
          autoComplete="new-password"
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-muted-foreground hover:bg-transparent"
          onClick={() => setShowPassword(prev => !prev)}
          aria-label={showPassword ? 'Hide password' : 'Show password'}
          tabIndex={-1}
        >
          {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </Button>
      </div>
    );
  };

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
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <InvochatLogo className="h-10 w-10" />
        <h1>InvoChat</h1>
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
            <div className="grid gap-2">
              <Label htmlFor="password">New Password</Label>
               <PasswordInput id="password" name="password" required />
            </div>
             <div className="grid gap-2">
              <Label htmlFor="confirmPassword">Confirm New Password</Label>
              <Input
                id="confirmPassword"
                name="confirmPassword"
                type="password"
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
